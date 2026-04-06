-- ============================================================================
-- 04 - Stored Procedures
-- ============================================================================
-- Creates 18 stored procedures for the POC tests:
--   Data Operations:
--     1. usp_InsertPlainData                 — insert into PlainData
--     2. usp_InsertEncryptedNoEnclave        — insert into EncryptedNoEnclave
--     3. usp_InsertEncryptedWithEnclave      — insert into EncryptedWithEnclave
--     4. usp_GetAllPlainData                 — select all from PlainData
--     5. usp_GetAllEncryptedNoEnclave        — select all from EncryptedNoEnclave
--     6. usp_GetAllEncryptedWithEnclave      — select all from EncryptedWithEnclave
--     7. usp_GetAllEncryptedNoEnclaveTarget  — select all from EncryptedNoEnclave_Target
--     8. usp_GetAllEncryptedWithEnclaveTarget— select all from EncryptedWithEnclave_Target
--     9. usp_UpdateSalaryEncryptedNoEnclave  — update Salary in EncryptedNoEnclave
--    10. usp_UpdateSalaryEncryptedWithEnclave— update Salary in EncryptedWithEnclave
--    11. usp_QueryBySsnEncryptedNoEnclave    — WHERE SSN = on EncryptedNoEnclave
--    12. usp_QueryBySsnEncryptedWithEnclave  — WHERE SSN = on EncryptedWithEnclave
--    13. usp_QueryByFullNameEncryptedNoEnclave  — WHERE FullName = on EncryptedNoEnclave
--    14. usp_QueryByFullNameEncryptedWithEnclave— WHERE FullName = on EncryptedWithEnclave
--   Test-specific:
--    15. usp_MoveEncryptedNoEnclaveData  — copy ciphertext between same-CEK tables (Test 2)
--    16. usp_MoveEncryptedWithEnclaveData — copy data between enclave tables (Test 3)
--    17. usp_SubstringNoEnclave           — SUBSTRING on non-enclave data (Test 4 - FAILS)
--    18. usp_SubstringWithEnclave         — SUBSTRING on enclave data (Test 5 - SUCCEEDS)
--
-- PREREQUISITES: Run 03-CreateTables.sql first. Seed data via the .NET app.
-- ============================================================================

-- ===========================================================================
-- INSERT stored procedures
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- Insert into PlainData
-- ---------------------------------------------------------------------------
IF OBJECT_ID('dbo.usp_InsertPlainData', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_InsertPlainData;
GO

CREATE PROCEDURE dbo.usp_InsertPlainData
    @SSN      CHAR(11),
    @FullName NVARCHAR(100),
    @Salary   MONEY
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.PlainData (SSN, FullName, Salary)
    VALUES (@SSN, @FullName, @Salary);
END;
GO

-- ---------------------------------------------------------------------------
-- Insert into EncryptedNoEnclave
-- ---------------------------------------------------------------------------
IF OBJECT_ID('dbo.usp_InsertEncryptedNoEnclave', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_InsertEncryptedNoEnclave;
GO

CREATE PROCEDURE dbo.usp_InsertEncryptedNoEnclave
    @SSN      CHAR(11),
    @FullName NVARCHAR(100),
    @Salary   MONEY
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.EncryptedNoEnclave (SSN, FullName, Salary)
    VALUES (@SSN, @FullName, @Salary);
END;
GO

-- ---------------------------------------------------------------------------
-- Insert into EncryptedWithEnclave
-- ---------------------------------------------------------------------------
IF OBJECT_ID('dbo.usp_InsertEncryptedWithEnclave', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_InsertEncryptedWithEnclave;
GO

CREATE PROCEDURE dbo.usp_InsertEncryptedWithEnclave
    @SSN      CHAR(11),
    @FullName NVARCHAR(100),
    @Salary   MONEY
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.EncryptedWithEnclave (SSN, FullName, Salary)
    VALUES (@SSN, @FullName, @Salary);
END;
GO

-- ===========================================================================
-- GET ALL stored procedures
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- Get all rows from PlainData
-- ---------------------------------------------------------------------------
IF OBJECT_ID('dbo.usp_GetAllPlainData', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_GetAllPlainData;
GO

CREATE PROCEDURE dbo.usp_GetAllPlainData
AS
BEGIN
    SET NOCOUNT ON;
    SELECT Id, SSN, FullName, Salary FROM dbo.PlainData;
END;
GO

-- ---------------------------------------------------------------------------
-- Get all rows from EncryptedNoEnclave
-- ---------------------------------------------------------------------------
IF OBJECT_ID('dbo.usp_GetAllEncryptedNoEnclave', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_GetAllEncryptedNoEnclave;
GO

CREATE PROCEDURE dbo.usp_GetAllEncryptedNoEnclave
AS
BEGIN
    SET NOCOUNT ON;
    SELECT Id, SSN, FullName, Salary FROM dbo.EncryptedNoEnclave;
END;
GO

-- ---------------------------------------------------------------------------
-- Get all rows from EncryptedWithEnclave
-- ---------------------------------------------------------------------------
IF OBJECT_ID('dbo.usp_GetAllEncryptedWithEnclave', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_GetAllEncryptedWithEnclave;
GO

CREATE PROCEDURE dbo.usp_GetAllEncryptedWithEnclave
AS
BEGIN
    SET NOCOUNT ON;
    SELECT Id, SSN, FullName, Salary FROM dbo.EncryptedWithEnclave;
END;
GO

-- ---------------------------------------------------------------------------
-- Get all rows from EncryptedNoEnclave_Target
-- ---------------------------------------------------------------------------
IF OBJECT_ID('dbo.usp_GetAllEncryptedNoEnclaveTarget', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_GetAllEncryptedNoEnclaveTarget;
GO

CREATE PROCEDURE dbo.usp_GetAllEncryptedNoEnclaveTarget
AS
BEGIN
    SET NOCOUNT ON;
    SELECT Id, SSN, FullName, Salary FROM dbo.EncryptedNoEnclave_Target;
END;
GO

-- ---------------------------------------------------------------------------
-- Get all rows from EncryptedWithEnclave_Target
-- ---------------------------------------------------------------------------
IF OBJECT_ID('dbo.usp_GetAllEncryptedWithEnclaveTarget', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_GetAllEncryptedWithEnclaveTarget;
GO

CREATE PROCEDURE dbo.usp_GetAllEncryptedWithEnclaveTarget
AS
BEGIN
    SET NOCOUNT ON;
    SELECT Id, SSN, FullName, Salary FROM dbo.EncryptedWithEnclave_Target;
END;
GO

-- ===========================================================================
-- UPDATE SALARY stored procedures
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- Update Salary in EncryptedNoEnclave by Id
-- ---------------------------------------------------------------------------
IF OBJECT_ID('dbo.usp_UpdateSalaryEncryptedNoEnclave', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_UpdateSalaryEncryptedNoEnclave;
GO

CREATE PROCEDURE dbo.usp_UpdateSalaryEncryptedNoEnclave
    @NewSalary MONEY,
    @Id        INT
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.EncryptedNoEnclave SET Salary = @NewSalary WHERE Id = @Id;
END;
GO

-- ---------------------------------------------------------------------------
-- Update Salary in EncryptedWithEnclave by Id
-- ---------------------------------------------------------------------------
IF OBJECT_ID('dbo.usp_UpdateSalaryEncryptedWithEnclave', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_UpdateSalaryEncryptedWithEnclave;
GO

CREATE PROCEDURE dbo.usp_UpdateSalaryEncryptedWithEnclave
    @NewSalary MONEY,
    @Id        INT
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.EncryptedWithEnclave SET Salary = @NewSalary WHERE Id = @Id;
END;
GO

-- ===========================================================================
-- QUERY BY SSN stored procedures
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- Query EncryptedNoEnclave by SSN
-- ---------------------------------------------------------------------------
IF OBJECT_ID('dbo.usp_QueryBySsnEncryptedNoEnclave', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_QueryBySsnEncryptedNoEnclave;
GO

CREATE PROCEDURE dbo.usp_QueryBySsnEncryptedNoEnclave
    @SSN CHAR(11)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT Id, SSN, FullName, Salary FROM dbo.EncryptedNoEnclave WHERE SSN = @SSN;
END;
GO

-- ---------------------------------------------------------------------------
-- Query EncryptedWithEnclave by SSN
-- ---------------------------------------------------------------------------
IF OBJECT_ID('dbo.usp_QueryBySsnEncryptedWithEnclave', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_QueryBySsnEncryptedWithEnclave;
GO

CREATE PROCEDURE dbo.usp_QueryBySsnEncryptedWithEnclave
    @SSN CHAR(11)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT Id, SSN, FullName, Salary FROM dbo.EncryptedWithEnclave WHERE SSN = @SSN;
END;
GO

-- ===========================================================================
-- QUERY BY FULLNAME stored procedures
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- Query EncryptedNoEnclave by FullName
-- ---------------------------------------------------------------------------
IF OBJECT_ID('dbo.usp_QueryByFullNameEncryptedNoEnclave', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_QueryByFullNameEncryptedNoEnclave;
GO

CREATE PROCEDURE dbo.usp_QueryByFullNameEncryptedNoEnclave
    @FullName NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT Id, SSN, FullName, Salary FROM dbo.EncryptedNoEnclave WHERE FullName = @FullName;
END;
GO

-- ---------------------------------------------------------------------------
-- Query EncryptedWithEnclave by FullName
-- ---------------------------------------------------------------------------
IF OBJECT_ID('dbo.usp_QueryByFullNameEncryptedWithEnclave', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_QueryByFullNameEncryptedWithEnclave;
GO

CREATE PROCEDURE dbo.usp_QueryByFullNameEncryptedWithEnclave
    @FullName NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT Id, SSN, FullName, Salary FROM dbo.EncryptedWithEnclave WHERE FullName = @FullName;
END;
GO

-- ===========================================================================
-- TEST-SPECIFIC stored procedures
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- Test 2: Move encrypted data (no enclave) from source to target
-- This works because source and target use the same CEK — the server copies
-- raw ciphertext without needing to decrypt.
-- ---------------------------------------------------------------------------
IF OBJECT_ID('dbo.usp_MoveEncryptedNoEnclaveData', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_MoveEncryptedNoEnclaveData;
GO

CREATE PROCEDURE dbo.usp_MoveEncryptedNoEnclaveData
AS
BEGIN
    SET NOCOUNT ON;

    -- Clear target table before copying
    DELETE FROM dbo.EncryptedNoEnclave_Target;

    -- Copy ciphertext directly — same CEK on source and target columns
    INSERT INTO dbo.EncryptedNoEnclave_Target (Id, SSN, FullName, Salary)
    SELECT Id, SSN, FullName, Salary
    FROM dbo.EncryptedNoEnclave;
END;
GO

-- ---------------------------------------------------------------------------
-- Test 3: Move encrypted data (with enclave) from source to target
-- Also copies ciphertext; enclave is available but not strictly needed here
-- since source and target share the same CEK.
-- ---------------------------------------------------------------------------
IF OBJECT_ID('dbo.usp_MoveEncryptedWithEnclaveData', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_MoveEncryptedWithEnclaveData;
GO

CREATE PROCEDURE dbo.usp_MoveEncryptedWithEnclaveData
AS
BEGIN
    SET NOCOUNT ON;

    -- Clear target table before copying
    DELETE FROM dbo.EncryptedWithEnclave_Target;

    -- Copy ciphertext — same enclave-enabled CEK on source and target
    INSERT INTO dbo.EncryptedWithEnclave_Target (Id, SSN, FullName, Salary)
    SELECT Id, SSN, FullName, Salary
    FROM dbo.EncryptedWithEnclave;
END;
GO

-- ---------------------------------------------------------------------------
-- Test 4: SUBSTRING on non-enclave encrypted column (EXPECTED TO FAIL)
-- Without an enclave, the server cannot decrypt the ciphertext to perform
-- SUBSTRING. This will raise an error like:
--   "Operand type clash: char(11) encrypted with (...) is incompatible with char"
-- The .NET app catches this error to demonstrate the limitation.
-- ---------------------------------------------------------------------------
IF OBJECT_ID('dbo.usp_SubstringNoEnclave', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_SubstringNoEnclave;
GO

CREATE PROCEDURE dbo.usp_SubstringNoEnclave
AS
BEGIN
    SET NOCOUNT ON;

    -- Use dynamic SQL so encryption validation is deferred to runtime.
    -- This will FAIL at runtime because the columns are encrypted without
    -- enclave support — the server cannot perform SUBSTRING on ciphertext.
    EXEC sp_executesql N'
        SELECT
            Id,
            SUBSTRING(SSN, 1, 3) AS SSN_Prefix
        FROM dbo.EncryptedNoEnclave;
    ';
END;
GO

-- ---------------------------------------------------------------------------
-- Test 5: SUBSTRING on enclave-enabled encrypted columns (EXPECTED TO SUCCEED)
-- With VBS enclave, the server decrypts inside the enclave to perform SUBSTRING.
-- Demonstrates both deterministic (SSN) and randomized (FullName) columns.
-- ---------------------------------------------------------------------------
IF OBJECT_ID('dbo.usp_SubstringWithEnclave', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_SubstringWithEnclave;
GO

CREATE PROCEDURE dbo.usp_SubstringWithEnclave
AS
BEGIN
    SET NOCOUNT ON;

    -- Use dynamic SQL so encryption validation is deferred to runtime.
    -- Enclaves decrypt in-place to compute SUBSTRING, then re-encrypt the result.
    -- Works on both deterministic and randomized encryption types.
    EXEC sp_executesql N'
        SELECT
            Id,
            SUBSTRING(SSN, 1, 3)      AS SSN_Prefix,
            SUBSTRING(FullName, 1, 5) AS Name_Prefix
        FROM dbo.EncryptedWithEnclave;
    ';
END;
GO
