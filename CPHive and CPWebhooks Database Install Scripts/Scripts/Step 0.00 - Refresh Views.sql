declare @Refreshviews table (sType char(2),
                             sName nvarchar(128),
                             sOwner varchar(128),
                             sSeq int)
--Table to hold names of Indexed views
declare @IndexViews table( sIndexViewName nvarchar(128) )

declare @ViewName nVarchar(128)
--Use sp_msdependencies - undocumented stored procedure that gives the dependencies at all levels in the right order
--sp_MSDependencies with Param NULL, 2 fetches the dependencies for all the views in the database.
insert into @Refreshviews(sType, sName, sOwner, sSeq )
  exec sp_msdependencies NULL, 2

--Get all the indexed or schemabound views and store the same
insert into @IndexViews(sIndexViewName)
  select name from sysobjects 
  where (objectproperty(id, 'isindexed')=1 or objectproperty(id, 'IsSchemaBound')=1) 
  and xtype='V' 

-- select only views (Views have sType = 4) that are dependent on other views
declare ViewCursor cursor for
  select sName from @Refreshviews where stype = 4 order by sSeq


open ViewCursor
fetch next from ViewCursor into @ViewName
while @@FETCH_STATUS = 0
begin
  begin try
   --CR 25338 Omit Indexed views 
   if not exists( select 1 from @IndexViews where sIndexViewName = @ViewName)
    exec('sp_refreshview ' + @ViewName)
  end try
  begin catch
    declare @ErrMsg nvarchar(500)
    set @ErrMsg = 'Error in view definition: ' + @ViewName
    raiserror(@ErrMsg,18,1)
  end catch
  -- Fetch next
  fetch next from ViewCursor into @ViewName
end
close ViewCursor
deallocate ViewCursor
go