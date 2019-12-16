-- List Users in particular database
select db_name() as DBName, *
from sys.database_principals
where sid not in (select sid
    from master.sys.server_principals)
    AND type_desc != 'DATABASE_ROLE' AND name != 'guest'


-- List Users from ALL databases
exec sp_msforeachdb ' use ? 
select db_name() as DBName,* from sys.database_principals  
where sid not in (select sid from master.sys.server_principals) 
AND type_desc != ''DATABASE_ROLE'' AND name != ''guest'' '

-- Generate FIX for Users in a particular database:
-- Script to generate Alter User script which can be used to map all orphan USERS with LOGINS in a particular database
select 'Alter User '  + name + ' WITH LOGIN = ' + name
from sys.database_principals
where sid not in (select sid
    from master.sys.server_principals)
    AND type_desc != 'DATABASE_ROLE' AND name != 'guest'


-- Generate FIX for Users in a ALL databases:
-- Script to generate Alter USER script which can be used to map all orphan users with logins in all databases
exec sp_msforeachdb ' use ? 
select ''Alter User ''  + name + '' WITH LOGIN = '' + name  from sys.database_principals  
where sid not in (select sid from master.sys.server_principals)  AND type_desc != ''DATABASE_ROLE'' AND name != ''guest'' '

-- Single user fix, example:
-- Script to map a particular database USER with a LOGIN:
ALTER USER userName WITH LOGIN = loginNam

--In each DB fix specific login:
--For each DB fix specific user
exec sp_MSforeachdb 'USE ?;
ALTER USER [AMK\Отгрузка - Просмотр] WITH LOGIN = [AMK\Отгрузка - Просмотр];'