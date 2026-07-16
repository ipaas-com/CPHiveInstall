--Created Via Ezno package. Package created on 8/19/2019. Trigger was last modified on: 7/29/2019 5:16:11 PM
IF EXISTS (SELECT name FROM sysobjects WHERE name = N'USR_IM_SKU_TR_CPHIVE_QUEUE')
DROP TRIGGER [dbo].[USR_IM_SKU_TR_CPHIVE_QUEUE]
GO


-- =============================================
-- Author:		Vance Berisford
-- Create date: 10/16/2019
-- Description:	This trigger will create product variant entries in the queue table. We use the SKU table because it combines changes that come from 
--	all three grid dimensions and is as close as CP comes to a product variant table. One effect of this is that we are shielded from changes that don't 
--	affect the number of grid dimensions. In other words, only grid dimension additions or subtractions are relevant to this trigger. There should not
--	be any functional loss from this, as the IM_GRID_DIM_x tables don't contain any real information other than dim data.
-- =============================================
CREATE TRIGGER [dbo].[USR_IM_SKU_TR_CPHIVE_QUEUE]
   ON  [dbo].[IM_SKU] 
   AFTER INSERT,DELETE,UPDATE
AS 
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE @UPD_TYP T_FLG, @UPD_TABLE T_DESCR
	SET @UPD_TABLE = 'product_variant'

	IF(EXISTS (SELECT TOP 1 1 FROM INSERTED))
		BEGIN
		IF(EXISTS (SELECT TOP 1 1 FROM DELETED))
			SET @UPD_TYP = 'U'
		ELSE
			SET @UPD_TYP = 'I'
		END
	ELSE
		BEGIN
		SET @UPD_TYP = 'D'
		END

	--Validate that we are subscribed to this scope
	DECLARE @SCOPE VARCHAR(1000)
	SET @SCOPE = REPLACE(@UPD_TABLE, '_', '/') + '/' + CASE WHEN @UPD_TYP = 'I' THEN 'created' WHEN @UPD_TYP = 'U' THEN 'updated' ELSE 'deleted' END

	DECLARE @SUBSCRIBED T_BOOL, @FILTER T_SQL_FILTER
	SELECT @SUBSCRIBED = SUBSCRIBED, @FILTER = [FILTER] FROM USR_CPHIVE_SUBSCRIPTION WHERE SCOPE = @SCOPE

	IF(COALESCE(@SUBSCRIBED, 'N') = 'N')
		RETURN

	CREATE TABLE [#TMP_UPDATED_IM_SKU] (
		[UPD_PK] [varchar] (800) NULL
	)

	IF(@FILTER IS NULL)
		BEGIN
		--Note that we save the PK with the tag DIM_x_UPR instead of DIM_x. In CPWebhooks, we deserialize this JSON into a GridEntity, which follows the IM_GRID_DIM_x convention of using the _UPR value.
		INSERT INTO [#TMP_UPDATED_IM_SKU](UPD_PK)
		SELECT DISTINCT '{"ITEM_NO":"' + dbo.[fnUsrCleanJSON](ITEM_NO) + '", "UNIT":"' + dbo.[fnUsrCleanJSON](UNIT) + '", "DIM_1_UPR":"' + UPPER(COALESCE(dbo.[fnUsrCleanJSON](DIM_1), '*')) + '", "DIM_2_UPR":"' + UPPER(COALESCE(dbo.[fnUsrCleanJSON](DIM_2), '*')) + '", "DIM_3_UPR":"' + UPPER(COALESCE(dbo.[fnUsrCleanJSON](DIM_3), '*')) + '"}' AS UPD_PK 
		FROM INSERTED 
		WHERE DIM_1 IS NOT NULL --We must ensure that this is a gridded item. We don't care about changes to non-gridded items
		UNION 
		SELECT DISTINCT '{"ITEM_NO":"' + dbo.[fnUsrCleanJSON](ITEM_NO) + '", "UNIT":"' + dbo.[fnUsrCleanJSON](UNIT) + '", "DIM_1_UPR":"' + UPPER(COALESCE(dbo.[fnUsrCleanJSON](DIM_1), '*')) + '", "DIM_2_UPR":"' + UPPER(COALESCE(dbo.[fnUsrCleanJSON](DIM_2), '*')) + '", "DIM_3_UPR":"' + UPPER(COALESCE(dbo.[fnUsrCleanJSON](DIM_3), '*')) + '"}' AS UPD_PK 
		FROM DELETED 
		WHERE DIM_1 IS NOT NULL --We must ensure that this is a gridded item. We don't care about changes to non-gridded items
		END
	ELSE
		BEGIN
		--The INSERTED and DELETED psuedotables are not available in dynamic SQL, so we've got to create a temp table of the entries
		CREATE TABLE [#TMP_IM_SKU] (
			[SKU_ID] [BIGINT] NOT NULL
		)

		INSERT INTO [#TMP_IM_SKU]
		SELECT DISTINCT SKU_ID FROM INSERTED
		UNION
		SELECT DISTINCT SKU_ID FROM DELETED

		DECLARE @SQL VARCHAR(MAX)
		SET @SQL = 'INSERT INTO [#TMP_UPDATED_IM_INV](UPD_PK)
		SELECT DISTINCT ''{"ITEM_NO":"'' + dbo.[fnUsrCleanJSON](T.ITEM_NO) + ''", "UNIT":"'' + dbo.[fnUsrCleanJSON](T.UNIT) + ''", "DIM_1_UPR":"'' + UPPER(COALESCE(dbo.[fnUsrCleanJSON](T.DIM_1), ''*'')) + ''", "DIM_2_UPR":"'' + UPPER(COALESCE(dbo.[fnUsrCleanJSON](T.DIM_2), ''*'')) + ''", "DIM_3_UPR":"'' + UPPER(COALESCE(dbo.[fnUsrCleanJSON](T.DIM_3), ''*'')) + ''"}'' AS UPD_PK 
		FROM [#TMP_IM_SKU] T JOIN IM_SKU ON T.SKU_ID = IM_SKU.SKU_ID WHERE ' + @FILTER
		EXEC(@SQL)
		END

	UPDATE USR_CPHIVE_QUEUE
	SET UPD_DT = GETDATE(),
		UPD_TYP = @UPD_TYP,
		ATTEMPTS = 0,
		RETRY_DT = NULL
	FROM [#TMP_UPDATED_IM_SKU] UPDATED
	WHERE USR_CPHIVE_QUEUE.UPD_TABLE = @UPD_TABLE
		AND UPDATED.UPD_PK = USR_CPHIVE_QUEUE.UPD_PK

	INSERT INTO USR_CPHIVE_QUEUE (UPD_TABLE, UPD_PK, UPD_DT, UPD_TYP)
	SELECT @UPD_TABLE, UPD_PK, GETDATE(), @UPD_TYP
	FROM [#TMP_UPDATED_IM_SKU] UPDATED
	WHERE NOT EXISTS (SELECT TOP 1 1 FROM USR_CPHIVE_QUEUE 
		WHERE USR_CPHIVE_QUEUE.UPD_TABLE = @UPD_TABLE 
			AND UPDATED.UPD_PK = USR_CPHIVE_QUEUE.UPD_PK)

END