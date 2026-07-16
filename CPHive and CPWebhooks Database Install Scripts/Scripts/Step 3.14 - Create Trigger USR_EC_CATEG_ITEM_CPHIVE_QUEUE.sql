
-- ============================================= 
-- Author:		Red Rook 
-- Create date: 2/9/23 
-- Description:	 
-- ============================================= 
CREATE TRIGGER [dbo].[USR_EC_CATEG_ITEM_CPHIVE_QUEUE]  
   ON  [dbo].[EC_CATEG_ITEM]  
   AFTER INSERT,DELETE 
AS  
BEGIN 
-- SET NOCOUNT ON added to prevent extra result sets from 
-- interfering with SELECT statements. 
SET NOCOUNT ON; 
DECLARE @UPD_TYP T_FLG, @UPD_TABLE T_DESCR 
SET @UPD_TABLE = 'ecommcategory_assignment' 
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
and table_name = 'EC_CATEG_ITEM' AND INFORMATION_SCHEMA.COLUMNS.COLUMN_NAME NOT IN ('ROW_TS','RS_UTC_DT','RS_STAT'))) 
RETURN 
END 
--Validate that we are subscribed to this scope 
DECLARE @SCOPE VARCHAR(1000) 
SET @SCOPE = REPLACE(@UPD_TABLE, '_', '/') + '/' + CASE WHEN @UPD_TYP = 'I' THEN 'created' WHEN @UPD_TYP = 'U' THEN 'updated' ELSE 'deleted' END 
DECLARE @SUBSCRIBED T_BOOL, @FILTER T_SQL_FILTER 
SELECT @SUBSCRIBED = SUBSCRIBED, @FILTER = [FILTER] FROM USR_CPHIVE_SUBSCRIPTION WHERE SCOPE = @SCOPE 
IF(COALESCE(@SUBSCRIBED, 'N') = 'N') 
RETURN 
CREATE TABLE [#TMP_UPDATED_EC_CATEG_ITEM] ( 
[UPD_PK] [varchar] (800) NULL 
) 
IF(@FILTER IS NULL) 
BEGIN 
INSERT INTO [#TMP_UPDATED_EC_CATEG_ITEM](UPD_PK) 
SELECT DISTINCT '{"ITEM_NO":"' + dbo.[fnUsrCleanJSON](ITEM_NO) + '", "CATEG_ID":"' + dbo.[fnUsrCleanJSON](CATEG_ID) + '"}' AS UPD_PK FROM INSERTED  
UNION  
SELECT DISTINCT '{"ITEM_NO":"' + dbo.[fnUsrCleanJSON](ITEM_NO) + '", "CATEG_ID":"' + dbo.[fnUsrCleanJSON](CATEG_ID) + '"}' AS UPD_PK FROM DELETED  
END 
ELSE 
BEGIN 
--The INSERTED and DELETED psuedotables are not available in dynamic SQL, so we've got to create a temp table of the entries 
CREATE TABLE [#TMP_EC_CATEG_ITEM] ( 
[ITEM_NO] [varchar] (20) NULL, 
[CATEG_ID] [varchar] (16) NULL 
) 
INSERT INTO [#TMP_EC_CATEG_ITEM] 
SELECT DISTINCT ITEM_NO, CATEG_ID FROM INSERTED 
UNION 
SELECT DISTINCT ITEM_NO, CATEG_ID FROM DELETED 
DECLARE @SQL VARCHAR(MAX) 
SET @SQL = 'INSERT INTO [#TMP_UPDATED_EC_CATEG_ITEM](UPD_PK)  
SELECT DISTINCT ''{"ITEM_NO":"'' + dbo.[fnUsrCleanJSON](T.ITEM_NO) + ''", "CATEG_ID":"'' + dbo.[fnUsrCleanJSON](T.CATEG_ID) + ''"}'' AS UPD_PK 
FROM [#TMP_EC_CATEG_ITEM] T JOIN EC_CATEG_ITEM ON T.ITEM_NO = EC_CATEG_ITEM.ITEM_NO AND T.CATEG_ID = EC_CATEG_ITEM.CATEG_ID WHERE ' + @FILTER 
EXEC(@SQL) 
END 
UPDATE USR_CPHIVE_QUEUE 
SET UPD_DT = GETDATE(), 
UPD_TYP = @UPD_TYP, 
ATTEMPTS = 0, 
RETRY_DT = NULL 
FROM [#TMP_UPDATED_EC_CATEG_ITEM] UPDATED 
WHERE USR_CPHIVE_QUEUE.UPD_TABLE = @UPD_TABLE 
AND UPDATED.UPD_PK = USR_CPHIVE_QUEUE.UPD_PK 
INSERT INTO USR_CPHIVE_QUEUE (UPD_TABLE, UPD_PK, UPD_DT, UPD_TYP) 
SELECT @UPD_TABLE, UPD_PK, GETDATE(), @UPD_TYP 
FROM [#TMP_UPDATED_EC_CATEG_ITEM] UPDATED 
WHERE NOT EXISTS (SELECT TOP 1 1 FROM USR_CPHIVE_QUEUE  
WHERE USR_CPHIVE_QUEUE.UPD_TABLE = @UPD_TABLE  
AND UPDATED.UPD_PK = USR_CPHIVE_QUEUE.UPD_PK) 
END 