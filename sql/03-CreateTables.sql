-- ============================================================================
-- 03 - Create Tables
-- ============================================================================
-- Creates 3 source tables (PlainData, EncryptedNoEnclave, EncryptedWithEnclave)
-- and 2 target tables (for data movement tests).
--
-- PREREQUISITES: Run 01 and 02 scripts first to create CMKs and CEKs.
--
-- NOTE: Data must be inserted via parameterized queries from a client with
-- Always Encrypted enabled (e.g., the .NET console app). Direct T-SQL INSERT
-- into encrypted columns will fail.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- PlainData — No encryption (baseline for comparison)
-- ---------------------------------------------------------------------------
IF OBJECT_ID('dbo.PlainData', 'U') IS NOT NULL DROP TABLE dbo.PlainData;
GO

CREATE TABLE dbo.PlainData (
    Id       INT           IDENTITY(1,1) PRIMARY KEY,
    SSN      CHAR(11)      NOT NULL,
    FullName NVARCHAR(100) NOT NULL,
    Salary   MONEY         NOT NULL
);
GO

-- ---------------------------------------------------------------------------
-- EncryptedNoEnclave — Always Encrypted WITHOUT enclave computations
-- SSN:      Deterministic (allows equality comparison via ciphertext match)
-- FullName: Randomized (strongest security, no server-side comparison)
-- Salary:   Randomized
-- ---------------------------------------------------------------------------
IF OBJECT_ID('dbo.EncryptedNoEnclave', 'U') IS NOT NULL DROP TABLE dbo.EncryptedNoEnclave;
GO

CREATE TABLE dbo.EncryptedNoEnclave (
    Id       INT           IDENTITY(1,1) PRIMARY KEY,
    SSN      CHAR(11)      COLLATE Latin1_General_BIN2
             ENCRYPTED WITH (
                 COLUMN_ENCRYPTION_KEY = [CEK_NoEnclave],
                 ENCRYPTION_TYPE = DETERMINISTIC,
                 ALGORITHM = 'AEAD_AES_256_CBC_HMAC_SHA_256'
             ) NOT NULL,
    FullName NVARCHAR(100) COLLATE Latin1_General_BIN2
             ENCRYPTED WITH (
                 COLUMN_ENCRYPTION_KEY = [CEK_NoEnclave],
                 ENCRYPTION_TYPE = DETERMINISTIC,
                 ALGORITHM = 'AEAD_AES_256_CBC_HMAC_SHA_256'
             ) NOT NULL,
    Salary   MONEY
             ENCRYPTED WITH (
                 COLUMN_ENCRYPTION_KEY = [CEK_NoEnclave],
                 ENCRYPTION_TYPE = DETERMINISTIC,
                 ALGORITHM = 'AEAD_AES_256_CBC_HMAC_SHA_256'
             ) NOT NULL
);
GO

-- ---------------------------------------------------------------------------
-- EncryptedWithEnclave — Always Encrypted WITH VBS enclave computations
-- Uses enclave-enabled CEK/CMK with RANDOMIZED encryption on all columns.
-- Enables rich computations (SUBSTRING, LIKE, comparison) inside the enclave.
-- ---------------------------------------------------------------------------
IF OBJECT_ID('dbo.EncryptedWithEnclave', 'U') IS NOT NULL DROP TABLE dbo.EncryptedWithEnclave;
GO

CREATE TABLE dbo.EncryptedWithEnclave (
    Id       INT           IDENTITY(1,1) PRIMARY KEY,
    SSN      CHAR(11)      COLLATE Latin1_General_BIN2
             ENCRYPTED WITH (
                 COLUMN_ENCRYPTION_KEY = [CEK_WithEnclave],
                 ENCRYPTION_TYPE = DETERMINISTIC,
                 ALGORITHM = 'AEAD_AES_256_CBC_HMAC_SHA_256'
             ) NOT NULL,
    FullName NVARCHAR(100) COLLATE Latin1_General_BIN2
             ENCRYPTED WITH (
                 COLUMN_ENCRYPTION_KEY = [CEK_WithEnclave],
                 ENCRYPTION_TYPE = DETERMINISTIC,
                 ALGORITHM = 'AEAD_AES_256_CBC_HMAC_SHA_256'
             ) NOT NULL,
    Salary   MONEY
             ENCRYPTED WITH (
                 COLUMN_ENCRYPTION_KEY = [CEK_WithEnclave],
                 ENCRYPTION_TYPE = DETERMINISTIC,
                 ALGORITHM = 'AEAD_AES_256_CBC_HMAC_SHA_256'
             ) NOT NULL
);
GO

-- ---------------------------------------------------------------------------
-- Target Tables — Used by data movement stored procedures (Tests 2 & 3)
-- Same column encryption as their source tables (same CEK).
-- ---------------------------------------------------------------------------
IF OBJECT_ID('dbo.EncryptedNoEnclave_Target', 'U') IS NOT NULL DROP TABLE dbo.EncryptedNoEnclave_Target;
GO

CREATE TABLE dbo.EncryptedNoEnclave_Target (
    Id       INT           PRIMARY KEY,  -- No IDENTITY; copied from source
    SSN      CHAR(11)      COLLATE Latin1_General_BIN2
             ENCRYPTED WITH (
                 COLUMN_ENCRYPTION_KEY = [CEK_NoEnclave],
                 ENCRYPTION_TYPE = DETERMINISTIC,
                 ALGORITHM = 'AEAD_AES_256_CBC_HMAC_SHA_256'
             ) NOT NULL,
    FullName NVARCHAR(100) COLLATE Latin1_General_BIN2
             ENCRYPTED WITH (
                 COLUMN_ENCRYPTION_KEY = [CEK_NoEnclave],
                 ENCRYPTION_TYPE = DETERMINISTIC,
                 ALGORITHM = 'AEAD_AES_256_CBC_HMAC_SHA_256'
             ) NOT NULL,
    Salary   MONEY
             ENCRYPTED WITH (
                 COLUMN_ENCRYPTION_KEY = [CEK_NoEnclave],
                 ENCRYPTION_TYPE = DETERMINISTIC,
                 ALGORITHM = 'AEAD_AES_256_CBC_HMAC_SHA_256'
             ) NOT NULL
);
GO

IF OBJECT_ID('dbo.EncryptedWithEnclave_Target', 'U') IS NOT NULL DROP TABLE dbo.EncryptedWithEnclave_Target;
GO

CREATE TABLE dbo.EncryptedWithEnclave_Target (
    Id       INT           PRIMARY KEY,  -- No IDENTITY; copied from source
    SSN      CHAR(11)      COLLATE Latin1_General_BIN2
             ENCRYPTED WITH (
                 COLUMN_ENCRYPTION_KEY = [CEK_WithEnclave],
                 ENCRYPTION_TYPE = DETERMINISTIC,
                 ALGORITHM = 'AEAD_AES_256_CBC_HMAC_SHA_256'
             ) NOT NULL,
    FullName NVARCHAR(100) COLLATE Latin1_General_BIN2
             ENCRYPTED WITH (
                 COLUMN_ENCRYPTION_KEY = [CEK_WithEnclave],
                 ENCRYPTION_TYPE = DETERMINISTIC,
                 ALGORITHM = 'AEAD_AES_256_CBC_HMAC_SHA_256'
             ) NOT NULL,
    Salary   MONEY
             ENCRYPTED WITH (
                 COLUMN_ENCRYPTION_KEY = [CEK_WithEnclave],
                 ENCRYPTION_TYPE = DETERMINISTIC,
                 ALGORITHM = 'AEAD_AES_256_CBC_HMAC_SHA_256'
             ) NOT NULL
);
GO

-- ---------------------------------------------------------------------------
-- Clear the procedure cache so sp_describe_parameter_encryption returns
-- fresh column-encryption metadata after the DROP/CREATE cycle above.
-- Without this, the driver may receive stale encryption-type info from a
-- previous run and encrypt parameters with the wrong type (e.g. DETERMINISTIC
-- instead of RANDOMIZED), causing an "Operand type clash" error.
-- ---------------------------------------------------------------------------
ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE;
GO
