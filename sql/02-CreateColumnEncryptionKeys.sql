-- ============================================================================
-- 02 - Create Column Encryption Keys (CEK)
-- ============================================================================
-- PREREQUISITES:
--   1. Run 01-CreateColumnMasterKeys.sql first.
--   2. The ENCRYPTED_VALUE must be generated during SSMS provisioning or via
--      PowerShell (New-SqlColumnEncryptionKey).
--
-- IMPORTANT: SSMS is the recommended way to create CEKs:
--   Right-click Always Encrypted Keys > Column Encryption Keys > New Column Encryption Key
--   Select the corresponding CMK and SSMS will generate the encrypted value.
--
-- The scripts below serve as reference for what gets created.
-- Replace <ENCRYPTED_VALUE_HEX> with the actual hex output from SSMS/PowerShell.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- CEK_NoEnclave — Column Encryption Key protected by CMK_NoEnclave
-- Used by: EncryptedNoEnclave and EncryptedNoEnclave_Target tables
-- ---------------------------------------------------------------------------
CREATE COLUMN ENCRYPTION KEY [CEK_NoEnclave]
WITH VALUES (
    COLUMN_MASTER_KEY = [CMK_NoEnclave],
    ALGORITHM = 'RSA_OAEP',
    ENCRYPTED_VALUE = <CEK_NO_ENCLAVE_ENCRYPTED_VALUE_HEX>
    -- Example: ENCRYPTED_VALUE = 0x01700000016C006F00630061006C...
    -- This hex value is the CEK wrapped (encrypted) by the CMK's RSA key in AKV.
);
GO

-- ---------------------------------------------------------------------------
-- CEK_WithEnclave — Column Encryption Key protected by CMK_WithEnclave
-- Used by: EncryptedWithEnclave and EncryptedWithEnclave_Target tables
-- ---------------------------------------------------------------------------
CREATE COLUMN ENCRYPTION KEY [CEK_WithEnclave]
WITH VALUES (
    COLUMN_MASTER_KEY = [CMK_WithEnclave],
    ALGORITHM = 'RSA_OAEP',
    ENCRYPTED_VALUE = <CEK_WITH_ENCLAVE_ENCRYPTED_VALUE_HEX>
    -- Example: ENCRYPTED_VALUE = 0x01700000016C006F00630061006C...
);
GO
