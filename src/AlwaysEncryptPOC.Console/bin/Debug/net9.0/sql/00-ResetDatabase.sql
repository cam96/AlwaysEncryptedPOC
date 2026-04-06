-- ============================================================================
-- 00 - Reset Database
-- ============================================================================
-- Drops all stored procedures and tables created by the POC scripts.
-- Does NOT drop Column Encryption Keys or Column Master Keys (those are
-- managed by 01/02 scripts and the PowerShell provisioning script).
--
-- This script is executed automatically by the .NET console app at startup
-- to ensure a clean slate before creating tables and stored procedures.
-- ============================================================================

-- Drop stored procedures
IF OBJECT_ID('dbo.usp_SubstringWithEnclave', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_SubstringWithEnclave;
IF OBJECT_ID('dbo.usp_SubstringNoEnclave', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_SubstringNoEnclave;
IF OBJECT_ID('dbo.usp_MoveEncryptedWithEnclaveData', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_MoveEncryptedWithEnclaveData;
IF OBJECT_ID('dbo.usp_MoveEncryptedNoEnclaveData', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_MoveEncryptedNoEnclaveData;

-- Drop target tables first (no FK dependencies, but logically depend on source)
IF OBJECT_ID('dbo.EncryptedWithEnclave_Target', 'U') IS NOT NULL
    DROP TABLE dbo.EncryptedWithEnclave_Target;
IF OBJECT_ID('dbo.EncryptedNoEnclave_Target', 'U') IS NOT NULL
    DROP TABLE dbo.EncryptedNoEnclave_Target;

-- Drop source tables
IF OBJECT_ID('dbo.EncryptedWithEnclave', 'U') IS NOT NULL
    DROP TABLE dbo.EncryptedWithEnclave;
IF OBJECT_ID('dbo.EncryptedNoEnclave', 'U') IS NOT NULL
    DROP TABLE dbo.EncryptedNoEnclave;
IF OBJECT_ID('dbo.PlainData', 'U') IS NOT NULL
    DROP TABLE dbo.PlainData;

PRINT 'Reset complete. All tables and stored procedures dropped.';
