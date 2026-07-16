--Created Via Ezno package. Package created on 7/31/2019. Trigger was last modified on: 7/31/2019 12:01:17 PM
IF EXISTS (SELECT name FROM sysobjects WHERE name = N'USR_IM_INV_CELL_CPHIVE_QUEUE')
DROP TRIGGER [dbo].[USR_IM_INV_CELL_CPHIVE_QUEUE]
GO

-- =============================================
-- Author:		Vance Berisford
-- Create date: 7/16/18
-- Description:	
-- =============================================
CREATE TRIGGER [dbo].[USR_IM_INV_CELL_CPHIVE_QUEUE] 
   ON  [dbo].[IM_INV_CELL] 
   AFTER INSERT,UPDATE,DELETE
AS 
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;
	
	DECLARE @UPD_TYP T_FLG, @UPD_TABLE T_DESCR
	SET @UPD_TABLE = 'product_variant_inventory'

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
	CREATE TABLE [#TMP_UPDATED] (
		[UPD_PK] [varchar] (800) NULL
	)

	IF(@FILTER IS NULL)
		BEGIN
		INSERT INTO [#TMP_UPDATED]
		SELECT DISTINCT '{"ITEM_NO":"' + dbo.[fnUsrCleanJSON](ITEM_NO) + '", "LOC_ID":"' + dbo.[fnUsrCleanJSON](LOC_ID) + '", "DIM_1_UPR":"' + dbo.[fnUsrCleanJSON](DIM_1_UPR) + '", "DIM_2_UPR":"' + dbo.[fnUsrCleanJSON](DIM_2_UPR) + '", "DIM_3_UPR":"' + dbo.[fnUsrCleanJSON](DIM_3_UPR) + '"}' AS UPD_PK FROM INSERTED 
		UNION 
		SELECT DISTINCT '{"ITEM_NO":"' + dbo.[fnUsrCleanJSON](ITEM_NO) + '", "LOC_ID":"' + dbo.[fnUsrCleanJSON](LOC_ID) + '", "DIM_1_UPR":"' + dbo.[fnUsrCleanJSON](DIM_1_UPR) + '", "DIM_2_UPR":"' + dbo.[fnUsrCleanJSON](DIM_2_UPR) + '", "DIM_3_UPR":"' + dbo.[fnUsrCleanJSON](DIM_3_UPR) + '"}' AS UPD_PK FROM DELETED 
		END
	ELSE
		BEGIN
		--The INSERTED and DELETED psuedotables are not available in dynamic SQL, so we've got to create a temp table of the entries
		CREATE TABLE [#TMP_IM_INV_CELL] (
			[ITEM_NO] [varchar] (20) NULL,
			[LOC_ID] [varchar] (10) NULL,
			[DIM_1_UPR] [varchar] (15) NULL,
			[DIM_2_UPR] [varchar] (15) NULL,
			[DIM_3_UPR] [varchar] (15) NULL,
		)

		INSERT INTO [#TMP_IM_INV_CELL]
		SELECT DISTINCT ITEM_NO, LOC_ID, DIM_1_UPR, DIM_2_UPR, DIM_3_UPR FROM INSERTED
		UNION
		SELECT DISTINCT ITEM_NO, LOC_ID, DIM_1_UPR, DIM_2_UPR, DIM_3_UPR FROM DELETED

		DECLARE @SQL VARCHAR(MAX)
		SET @SQL = 'INSERT INTO [#TMP_UPDATED]
		SELECT  DISTINCT ''{"ITEM_NO":"'' + dbo.[fnUsrCleanJSON](T.ITEM_NO) + ''", "LOC_ID":"'' + dbo.[fnUsrCleanJSON](T.LOC_ID) + ''", "DIM_1_UPR":"'' + dbo.[fnUsrCleanJSON](T.DIM_1_UPR) + ''", "DIM_2_UPR":"'' + dbo.[fnUsrCleanJSON](T.DIM_2_UPR) + ''", "DIM_3_UPR":"'' + dbo.[fnUsrCleanJSON](T.DIM_3_UPR) + ''"}'' AS UPD_PK
		FROM [#TMP_IM_INV_CELL] T JOIN IM_INV_CELL ON T.ITEM_NO = IM_INV_CELL.ITEM_NO AND T.LOC_ID = IM_INV_CELL.LOC_ID AND T.DIM_1_UPR = IM_INV_CELL.DIM_1_UPR AND T.DIM_2_UPR = IM_INV_CELL.DIM_2_UPR 
		AND T.DIM_3_UPR = IM_INV_CELL.DIM_3_UPR WHERE ' + @FILTER
		EXEC(@SQL)
		END

	UPDATE USR_CPHIVE_QUEUE
	SET UPD_DT = GETDATE(),
		UPD_TYP = @UPD_TYP,
		ATTEMPTS = 0,
		RETRY_DT = NULL
	FROM [#TMP_UPDATED] UPDATED
	WHERE USR_CPHIVE_QUEUE.UPD_TABLE = @UPD_TABLE
		AND UPDATED.UPD_PK = USR_CPHIVE_QUEUE.UPD_PK

    INSERT INTO USR_CPHIVE_QUEUE (UPD_TABLE, UPD_PK, UPD_DT, UPD_TYP)
	SELECT @UPD_TABLE, UPD_PK, GETDATE(), @UPD_TYP
	FROM [#TMP_UPDATED] UPDATED
	WHERE NOT EXISTS (SELECT TOP 1 1 FROM USR_CPHIVE_QUEUE 
		WHERE USR_CPHIVE_QUEUE.UPD_TABLE = @UPD_TABLE 
			AND UPDATED.UPD_PK = USR_CPHIVE_QUEUE.UPD_PK)
END