USE master
GO
/* Verify master key */
SELECT * FROM sys.symmetric_keys WHERE name LIKE '%MS_DatabaseMasterKey%'
GO

/* if there are no records found, then it means there was no predefined Master Key. 
 To create a Master Key, you can execute the below mentioned TSQL code. */
 
/* Create master key */
CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'repL@dm1n';
GO
/* Backup master key */
OPEN MASTER KEY DECRYPTION BY PASSWORD = 'repL@dm1n';
GO
BACKUP MASTER KEY TO FILE = 'G:\cert\masterkey.mk' 
    ENCRYPTION BY PASSWORD = 'repL@dm1n';
GO

/* Create Certificate */
CREATE CERTIFICATE server_cert2 WITH SUBJECT = 'Server Certificate';
GO

/* Verify Certificate */
SELECT * FROM sys.certificates where [name] = 'server_cert2'
GO

/* Backup certificate */
BACKUP CERTIFICATE server_cert TO FILE = 'G:\cert\server_cert2.cer'
   WITH PRIVATE KEY (
         FILE = 'G:\cert\server_cert2.pvk',
         ENCRYPTION BY PASSWORD = 'repL@dm1n');
GO

--use rev database
USE test1
GO
/* Create Encryption key */
CREATE DATABASE ENCRYPTION KEY
   WITH ALGORITHM = AES_256
   ENCRYPTION BY SERVER CERTIFICATE server_cert2;
GO


/* Encrypt database */
ALTER DATABASE test1 SET ENCRYPTION ON;
GO

/* Verify Encryption */
SELECT 
DB_NAME(database_id) AS DatabaseName
,Encryption_State AS EncryptionState
,key_algorithm AS Algorithm
,key_length AS KeyLength
FROM sys.dm_database_encryption_keys
GO
SELECT 
NAME AS DatabaseName
,IS_ENCRYPTED AS IsEncrypted 
FROM sys.databases where name ='test1'
GO
