-- ============================================================================
-- 05 - Cleanup
-- ============================================================================
-- Drops all POC objects in reverse dependency order.
-- Run this when you're done with the POC.
--
-- NOTE: To fully clean up Azure resources, also run:
--   az group delete --name rg-alwaysencrypt-poc --yes --no-wait
-- ============================================================================

-- Drop stored procedures
IF OBJECT_ID('dbo.usp_SubstringWithEnclave', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_SubstringWithEnclave;
GO
IF OBJECT_ID('dbo.usp_SubstringNoEnclave', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_SubstringNoEnclave;
GO
IF OBJECT_ID('dbo.usp_MoveEncryptedWithEnclaveData', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_MoveEncryptedWithEnclaveData;
GO
IF OBJECT_ID('dbo.usp_MoveEncryptedNoEnclaveData', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_MoveEncryptedNoEnclaveData;
GO

-- Drop target tables (depend on CEKs)
IF OBJECT_ID('dbo.EncryptedWithEnclave_Target', 'U') IS NOT NULL
    DROP TABLE dbo.EncryptedWithEnclave_Target;
GO
IF OBJECT_ID('dbo.EncryptedNoEnclave_Target', 'U') IS NOT NULL
    DROP TABLE dbo.EncryptedNoEnclave_Target;
GO

-- Drop source tables (depend on CEKs)
IF OBJECT_ID('dbo.EncryptedWithEnclave', 'U') IS NOT NULL
    DROP TABLE dbo.EncryptedWithEnclave;
GO
IF OBJECT_ID('dbo.EncryptedNoEnclave', 'U') IS NOT NULL
    DROP TABLE dbo.EncryptedNoEnclave;
GO
IF OBJECT_ID('dbo.PlainData', 'U') IS NOT NULL
    DROP TABLE dbo.PlainData;
GO

-- Drop Column Encryption Keys (depend on CMKs)
IF EXISTS (SELECT 1 FROM sys.column_encryption_keys WHERE name = 'CEK_WithEnclave')
    DROP COLUMN ENCRYPTION KEY [CEK_WithEnclave];
GO
IF EXISTS (SELECT 1 FROM sys.column_encryption_keys WHERE name = 'CEK_NoEnclave')
    DROP COLUMN ENCRYPTION KEY [CEK_NoEnclave];
GO

-- Drop Column Master Keys
IF EXISTS (SELECT 1 FROM sys.column_master_keys WHERE name = 'CMK_WithEnclave')
    DROP COLUMN MASTER KEY [CMK_WithEnclave];
GO
IF EXISTS (SELECT 1 FROM sys.column_master_keys WHERE name = 'CMK_NoEnclave')
    DROP COLUMN MASTER KEY [CMK_NoEnclave];
GO

PRINT 'Cleanup complete. All POC objects have been removed.';
GO
