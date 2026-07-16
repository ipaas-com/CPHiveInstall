--Created Via Ezno package. Package created on 3/3/2020. Function was last modified on: 3/3/2020 11:21:28 AM
IF EXISTS (SELECT name FROM sysobjects WHERE name = N'fnUsrCleanJSON')
DROP FUNCTION [dbo].[fnUsrCleanJSON]
GO
create function [dbo].[fnUsrCleanJSON](
  @S varchar(max)
) returns varchar(max)
as
begin
	select @S = replace(@S, '\', '\\')
	select @S = replace(@S, '"', '\"')
	return @S
end
 
