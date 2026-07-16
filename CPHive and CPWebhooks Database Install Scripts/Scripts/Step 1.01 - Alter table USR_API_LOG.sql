--Created Via Ezno package. Package created on 7/31/2019.
/*
 * Creating table USR_API_LOG
 *
 */
IF(NOT EXISTS(SELECT TOP 1 1 FROM Information_Schema.Tables WHERE TABLE_NAME = 'USR_API_LOG')) 
    BEGIN
    CREATE TABLE [dbo].[USR_API_LOG](
        [SESS_ID] uniqueidentifier NOT NULL,
        [LIN_ID] uniqueidentifier NOT NULL,
    CONSTRAINT [PK_USR_API_LOG] PRIMARY KEY CLUSTERED 
    (
        [SESS_ID] ASC,
        [LIN_ID] ASC
    )
    ) ON [PRIMARY]
    END
GO


IF(NOT EXISTS(SELECT TOP 1 1 FROM Information_schema.Columns C WHERE C.TABLE_NAME = 'USR_API_LOG' AND C.COLUMN_NAME = 'ACTION_DT')) 
    BEGIN
    ALTER TABLE [dbo].[USR_API_LOG] ADD [ACTION_DT] datetime NULL
    END
GO


IF(NOT EXISTS(SELECT TOP 1 1 FROM Information_schema.Columns C WHERE C.TABLE_NAME = 'USR_API_LOG' AND C.COLUMN_NAME = 'ACTION_TYP')) 
    BEGIN
    ALTER TABLE [dbo].[USR_API_LOG] ADD [ACTION_TYP] varchar(255) NULL
    END
GO


IF(NOT EXISTS(SELECT TOP 1 1 FROM Information_schema.Columns C WHERE C.TABLE_NAME = 'USR_API_LOG' AND C.COLUMN_NAME = 'SEVERITY')) 
    BEGIN
    ALTER TABLE [dbo].[USR_API_LOG] ADD [SEVERITY] varchar(1) NULL
    END
GO


IF(NOT EXISTS(SELECT TOP 1 1 FROM Information_schema.Columns C WHERE C.TABLE_NAME = 'USR_API_LOG' AND C.COLUMN_NAME = 'DATA')) 
    BEGIN
    ALTER TABLE [dbo].[USR_API_LOG] ADD [DATA] varchar(MAX) NULL
    END
GO