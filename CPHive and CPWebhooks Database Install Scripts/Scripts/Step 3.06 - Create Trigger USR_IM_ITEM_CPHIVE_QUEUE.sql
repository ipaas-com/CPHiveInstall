--Created Via Ezno package. Package created on 7/31/2019. Trigger was last modified on: 7/30/2019 5:03:39 PM
IF EXISTS (SELECT name FROM sysobjects WHERE name = N'USR_IM_ITEM_CPHIVE_QUEUE')
DROP TRIGGER [dbo].[USR_IM_ITEM_CPHIVE_QUEUE]
GO
-- =============================================
-- Author:		Vance Berisford
-- Create date: 7/16/18
-- Description:	
-- =============================================
CREATE TRIGGER [dbo].[USR_IM_ITEM_CPHIVE_QUEUE] 
   ON  [dbo].[IM_ITEM] 
   AFTER INSERT,UPDATE,DELETE
AS 
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;
	
	DECLARE @UPD_TYP T_FLG, @UPD_TABLE T_DESCR
	SET @UPD_TABLE = 'product'

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

	----If this update only includes the following three fields, we ignore it: 'ROW_TS','RS_UTC_DT','RS_STAT'
	IF(@UPD_TYP = 'U')
		BEGIN
		IF(NOT EXISTS (select TOP 1 1 from INFORMATION_SCHEMA.COLUMNS where substring(columns_updated(), (-1 + columnproperty(object_id(table_schema + '.' + table_name, 'U'), column_name, 'columnId')) / 8 + 1, 1) & power(2, (-1 + columnproperty(object_id(table_schema + '.' + table_name, 'U'), column_name, 'columnId')) % 8 ) > 0
			and table_name = 'IM_ITEM' AND INFORMATION_SCHEMA.COLUMNS.COLUMN_NAME NOT IN ('ROW_TS','RS_UTC_DT','RS_STAT')))
			RETURN
		END

	--Validate that we are subscribed to this scope
	DECLARE @SCOPE VARCHAR(1000)
	SET @SCOPE = REPLACE(@UPD_TABLE, '_', '/') + '/' + CASE WHEN @UPD_TYP = 'I' THEN 'created' WHEN @UPD_TYP = 'U' THEN 'updated' ELSE 'deleted' END

	DECLARE @SUBSCRIBED T_BOOL, @FILTER T_SQL_FILTER
	SELECT @SUBSCRIBED = SUBSCRIBED, @FILTER = [FILTER] FROM USR_CPHIVE_SUBSCRIPTION WHERE SCOPE = @SCOPE

	IF(COALESCE(@SUBSCRIBED, 'N') = 'N')
		RETURN

	CREATE TABLE [#TMP_UPDATED_IM_ITEM] (
		[UPD_PK] [varchar] (800) NULL
	)

	IF(@FILTER IS NULL)
		BEGIN
		INSERT INTO [#TMP_UPDATED_IM_ITEM]
		SELECT DISTINCT '{"ITEM_NO":"' + dbo.[fnUsrCleanJSON](ITEM_NO) + '"}' AS UPD_PK FROM INSERTED 
		UNION 
		SELECT DISTINCT '{"ITEM_NO":"' + dbo.[fnUsrCleanJSON](ITEM_NO) + '"}' AS UPD_PK FROM DELETED 
		END
	ELSE
		BEGIN
		--The INSERTED and DELETED psuedotables are not available in dynamic SQL, so we've got to create a temp table of the entries
		CREATE TABLE [#TMP_IM_ITEM] (
			[ITEM_NO] [varchar] (20) NULL
		)

		INSERT INTO [#TMP_IM_ITEM]
		SELECT DISTINCT ITEM_NO FROM INSERTED
		UNION
		SELECT DISTINCT ITEM_NO FROM DELETED

		DECLARE @SQL VARCHAR(MAX)
		SET @SQL = 'INSERT INTO [#TMP_UPDATED_IM_ITEM]
		SELECT DISTINCT ''{"ITEM_NO":"'' + dbo.[fnUsrCleanJSON](T.ITEM_NO) + ''"}'' AS UPD_PK
		FROM [#TMP_IM_ITEM] T JOIN IM_ITEM ON T.ITEM_NO = IM_ITEM.ITEM_NO WHERE ' + @FILTER
		EXEC(@SQL)
		END

	UPDATE USR_CPHIVE_QUEUE
	SET UPD_DT = GETDATE(),
		UPD_TYP = @UPD_TYP,
		ATTEMPTS = 0,
		RETRY_DT = NULL
	FROM [#TMP_UPDATED_IM_ITEM] UPDATED
	WHERE USR_CPHIVE_QUEUE.UPD_TABLE = @UPD_TABLE
		AND UPDATED.UPD_PK = USR_CPHIVE_QUEUE.UPD_PK

    INSERT INTO USR_CPHIVE_QUEUE (UPD_TABLE, UPD_PK, UPD_DT, UPD_TYP)
	SELECT @UPD_TABLE, UPD_PK, GETDATE(), @UPD_TYP
	FROM [#TMP_UPDATED_IM_ITEM] UPDATED
	WHERE NOT EXISTS (SELECT TOP 1 1 FROM USR_CPHIVE_QUEUE 
		WHERE USR_CPHIVE_QUEUE.UPD_TABLE = @UPD_TABLE 
			AND UPDATED.UPD_PK = USR_CPHIVE_QUEUE.UPD_PK)
END
