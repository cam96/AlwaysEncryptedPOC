# Always Encrypted POC — Complete Run Guide

This guide walks through deploying and running the Always Encrypted proof of concept from scratch. Follow every step in order.

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Gather Your Configuration Values](#2-gather-your-configuration-values)
3. [Deploy Azure Infrastructure (Bicep)](#3-deploy-azure-infrastructure-bicep)
4. [Verify Deployment Outputs](#4-verify-deployment-outputs)
5. [Provision Always Encrypted Keys (SSMS — Manual)](#5-provision-always-encrypted-keys-ssms--manual)
6. [Create Tables and Stored Procedures (SSMS — Manual)](#6-create-tables-and-stored-procedures-ssms--manual)
7. [Configure the .NET Console App](#7-configure-the-net-console-app)
8. [Run the Console App](#8-run-the-console-app)
9. [Expected Results](#9-expected-results)
10. [Cleanup](#10-cleanup)
11. [Troubleshooting](#11-troubleshooting)

---

## 1. Prerequisites

Install or verify each of the following **before starting**:

| Tool | Version | Download |
|---|---|---|
| **Azure CLI** | 2.60+ | https://learn.microsoft.com/en-us/cli/azure/install-azure-cli |
| **.NET 9 SDK** | 9.0.300+ | https://dotnet.microsoft.com/download/dotnet/9.0 |
| **SSMS** (SQL Server Management Studio) | 20.0+ | https://learn.microsoft.com/en-us/sql/ssms/download-sql-server-management-studio-ssms |
| **Azure Subscription** | — | This POC targets: `Visual Studio Enterprise Subscription` (`15442e45-facf-4f45-9d12-a54f479bc10f`) |

**Required Azure permissions**: You must have **Contributor** (or higher) on the target subscription to deploy the Bicep templates.

---

## 2. Gather Your Configuration Values

Open a PowerShell terminal and collect three values you'll need for deployment.

### 2a. Log in to Azure

```powershell
az login --tenant 2fa5d74-1fba-458e-b12c-d2a157bccca6
az account set --subscription "af2sd45-facf-4f45-9d12-a54f479bc10f"
```

### 2b. Get your Azure AD Object ID

```powershell
az ad signed-in-user show --query id -o tsv
```

Copy the GUID output — this is your `principalId`.

### 2c. Get your User Principal Name (UPN)

```powershell
az ad signed-in-user show --query userPrincipalName -o tsv
```

Copy the output (e.g., `yourname@yourdomain.com`) — this is your `principalName`.

### 2d. Get your public IP address

```powershell
(Invoke-WebRequest -Uri https://api.ipify.org).Content
```

Copy the IP — this is your `clientIpAddress`.

---

## 3. Deploy Azure Infrastructure (Bicep)

### 3a. Update the parameter file

Open `infra/main.bicepparam` and replace the three placeholders with values from Step 2:

```bicep
using './main.bicep'

param location = 'canadacentral'
param principalId = 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'   // from Step 2b
param principalName = 'yourname@yourdomain.com'              // from Step 2c
param clientIpAddress = '203.0.113.42'                        // from Step 2d
```

### 3b. Run the Bicep deployment

From the repository root:

```powershell
az deployment sub create `
  --name AlwaysEncryptPOC `
  --location canadacentral `
  --subscription 15442e45-facf-4f45-9d12-a54f479bc10f `
  --template-file infra/main.bicep `
  --parameters infra/main.bicepparam
```

**This deploys:**
- Resource group: `rg-alwaysencrypt-poc`
- Azure Key Vault (Standard SKU, RBAC authorization) with two RSA 4096-bit keys
- Azure SQL Server (Azure AD-only authentication) with a GP_Gen5_2 database (VBS enclaves enabled)
- Two RBAC role assignments on Key Vault (Crypto Officer + Crypto User)
- SQL firewall rules for your IP and Azure services

**Expected duration:** 3–8 minutes.

---

## 4. Verify Deployment Outputs

After the deployment completes, retrieve the outputs:

```powershell
az deployment sub show `
  --name AlwaysEncryptPOC `
  --subscription 15442e45-facf-4f45-9d12-a54f479bc10f `
  --query properties.outputs `
  --output table
```

You need the following values for later steps:

| Output | Example Value | Used In |
|---|---|---|
| `sqlServerFqdn` | `sql-ae-poc-abc123.database.windows.net` | appsettings.json, SSMS connection |
| `databaseName` | `AlwaysEncryptPocDb` | SSMS connection |
| `keyVaultName` | `kv-ae-poc-abc123` | Verification only |
| `cmkNoEnclaveKeyUri` | `https://kv-ae-poc-abc123.vault.azure.net/keys/CMK-NoEnclave/...` | SSMS AKV key selection (reference) |
| `cmkWithEnclaveKeyUri` | `https://kv-ae-poc-abc123.vault.azure.net/keys/CMK-WithEnclave/...` | SSMS AKV key selection (reference) |

> **Tip:** You can also find these in the Azure Portal under the resource group `rg-alwaysencrypt-poc`.

### Verify Key Vault has the keys

```powershell
az keyvault key list --vault-name <keyVaultName> --output table
```

You should see `CMK-NoEnclave` and `CMK-WithEnclave`.

### Verify the database has VBS enclaves enabled

```powershell
az sql db show `
  --resource-group rg-alwaysencrypt-poc `
  --server <sql-server-name> `
  --name AlwaysEncryptPocDb `
  --query preferredEnclaveType `
  --output tsv
```

Should return: `VBS`

---

## 5. Provision Always Encrypted Keys

This is the most critical step. Bicep created the RSA keys in Key Vault, but the **Column Master Key (CMK) metadata** and **Column Encryption Key (CEK) data** inside SQL must be provisioned separately. These cannot be created by regular T-SQL alone because the encrypted key values require cryptographic operations against Azure Key Vault.

You have two options:
- **Option A — PowerShell script** (recommended, fully automated)
- **Option B — SSMS wizard** (manual, click-through)

---

### Option A: PowerShell Script (Automated)

The `SqlServer` PowerShell module has cmdlets that handle all AKV cryptographic operations (key wrapping, enclave signature generation) automatically.

#### Prerequisites

```powershell
Install-Module -Name SqlServer -Force -AllowClobber -Scope CurrentUser
Install-Module -Name Az.Accounts -Force -Scope CurrentUser
```

#### Run the provisioning script

From the repository root:

```powershell
# 1. Log in to Azure (if not already)
Connect-AzAccount -Tenant '3d8e5d74-1fba-458e-b12c-d2a157bccca6'
Set-AzContext -Subscription '15442e45-facf-4f45-9d12-a54f479bc10f'

# 2. Get deployment outputs
$outputs = az deployment sub show --name AlwaysEncryptPOC `
  --subscription 15442e45-facf-4f45-9d12-a54f479bc10f `
  --query properties.outputs -o json | ConvertFrom-Json

# 3. Run the script
.\sql\Provision-AlwaysEncryptedKeys.ps1 `
  -SqlServerFqdn $outputs.sqlServerFqdn.value `
  -CmkNoEnclaveKeyUri $outputs.cmkNoEnclaveKeyUri.value `
  -CmkWithEnclaveKeyUri $outputs.cmkWithEnclaveKeyUri.value
```

The script will:
1. Authenticate to Azure AD (interactive prompt for AKV access)
2. Create `CMK_NoEnclave` — registers AKV key path as a standard Column Master Key
3. Create `CMK_WithEnclave` — registers AKV key path with a signed enclave attestation (uses the `sign` permission on AKV)
4. Create `CEK_NoEnclave` — generates a random AES-256 key, wraps it with the RSA key via AKV (`wrapKey`), stores the ciphertext in SQL
5. Create `CEK_WithEnclave` — same process using the enclave CMK

> **Why can't plain T-SQL do this?** The `ENCRYPTED_VALUE` in a CEK definition is the symmetric key wrapped by the RSA key in AKV — SQL Server can't call AKV. The `ENCLAVE_COMPUTATIONS SIGNATURE` on a CMK is produced by signing with the RSA private key — also requires AKV access. The SqlServer module (and SSMS) act as an intermediary that performs these crypto operations client-side.

After the script completes, skip to [Step 5f](#5f-verify-keys-were-created) to verify.

---

### Option B: SSMS Wizard (Manual)

### 5a. Connect to the database in SSMS

1. Open SSMS.
2. Server name: **paste the `sqlServerFqdn`** from Step 4 (e.g., `sql-ae-poc-abc123.database.windows.net`).
3. Authentication: **Microsoft Entra Default** (or "Azure Active Directory - Default").
4. Database: `AlwaysEncryptPocDb` (enter in the **Options > Connection Properties** tab).
5. Click **Connect**.

> **Important**: Do NOT enable "Column Encryption Setting" on this connection. You want a regular connection for key provisioning.

### 5b. Create CMK_NoEnclave (standard, no enclave computations)

1. In Object Explorer, expand: **AlwaysEncryptPocDb > Security > Always Encrypted Keys > Column Master Keys**.
2. Right-click **Column Master Keys** → **New Column Master Key…**
3. Set the following:
   - **Name**: `CMK_NoEnclave`
   - **Key store**: Select **Azure Key Vault** from the dropdown
4. Click **Sign In** and authenticate with your Azure AD account.
5. After signing in, the dropdown will populate with your Key Vault. Select the key **`CMK-NoEnclave`**.
6. **Ensure "Allow enclave computations" is UNCHECKED** (this is the non-enclave key).
7. Click **OK**.

### 5c. Create CMK_WithEnclave (enclave-enabled)

1. Right-click **Column Master Keys** → **New Column Master Key…**
2. Set the following:
   - **Name**: `CMK_WithEnclave`
   - **Key store**: **Azure Key Vault**
3. Sign in (if prompted) and select the key **`CMK-WithEnclave`**.
4. **CHECK "Allow enclave computations"**.
5. Click **OK**.

> SSMS will use the `sign` permission on the Key Vault key to generate the enclave computation signature. This requires the **Key Vault Crypto Officer** role (assigned by Bicep).

### 5d. Create CEK_NoEnclave

1. In Object Explorer, expand: **Always Encrypted Keys > Column Encryption Keys**.
2. Right-click **Column Encryption Keys** → **New Column Encryption Key…**
3. Set the following:
   - **Name**: `CEK_NoEnclave`
   - **Column master key**: Select **`CMK_NoEnclave`** from the dropdown
4. Click **OK**.

> SSMS generates a random 256-bit symmetric key, wraps it using the RSA key in Key Vault (`wrapKey` operation), and stores the encrypted value in SQL metadata.

### 5e. Create CEK_WithEnclave

1. Right-click **Column Encryption Keys** → **New Column Encryption Key…**
2. Set the following:
   - **Name**: `CEK_WithEnclave`
   - **Column master key**: Select **`CMK_WithEnclave`**
3. Click **OK**.

### 5f. Verify keys were created

In SSMS, run:

```sql
SELECT name, column_master_key_id FROM sys.column_encryption_keys;
SELECT name, key_store_provider_name, key_path FROM sys.column_master_keys;
```

You should see:
- 2 Column Master Keys: `CMK_NoEnclave`, `CMK_WithEnclave`
- 2 Column Encryption Keys: `CEK_NoEnclave`, `CEK_WithEnclave`

---

## 6. Create Tables and Stored Procedures (SSMS — Manual)

Still in SSMS, connected to `AlwaysEncryptPocDb`, run the following SQL scripts **in this exact order**:

### 6a. Create tables

Open and execute `sql/03-CreateTables.sql`.

This creates 5 tables:

| Table | Purpose |
|---|---|
| `dbo.PlainData` | Unencrypted baseline |
| `dbo.EncryptedNoEnclave` | AE with deterministic (SSN) + randomized (FullName, Salary) — no enclave |
| `dbo.EncryptedWithEnclave` | AE with deterministic (SSN) + randomized (FullName, Salary) — VBS enclave |
| `dbo.EncryptedNoEnclave_Target` | Target for data movement test (Test 2) |
| `dbo.EncryptedWithEnclave_Target` | Target for data movement test (Test 3) |

### 6b. Create stored procedures

Open and execute `sql/04-StoredProcedures.sql`.

This creates 4 stored procedures:

| Stored Procedure | Purpose | Expected Behavior |
|---|---|---|
| `dbo.usp_MoveEncryptedNoEnclaveData` | Copies ciphertext from source to target (same CEK) | Succeeds |
| `dbo.usp_MoveEncryptedWithEnclaveData` | Copies data between enclave tables | Succeeds |
| `dbo.usp_SubstringNoEnclave` | SUBSTRING on non-enclave encrypted column | **Fails at runtime** |
| `dbo.usp_SubstringWithEnclave` | SUBSTRING on enclave encrypted columns | Succeeds |

> **Note**: Do NOT run `sql/01-CreateColumnMasterKeys.sql` or `sql/02-CreateColumnEncryptionKeys.sql`. Those are reference scripts showing what SSMS created internally during Step 5. Running them manually would fail because they contain placeholder values.

### 6c. Verify the tables and procedures exist

```sql
SELECT name FROM sys.tables WHERE schema_id = SCHEMA_ID('dbo') ORDER BY name;
SELECT name FROM sys.procedures WHERE schema_id = SCHEMA_ID('dbo') ORDER BY name;
```

Expected tables: `EncryptedNoEnclave`, `EncryptedNoEnclave_Target`, `EncryptedWithEnclave`, `EncryptedWithEnclave_Target`, `PlainData`

Expected procedures: `usp_MoveEncryptedNoEnclaveData`, `usp_MoveEncryptedWithEnclaveData`, `usp_SubstringNoEnclave`, `usp_SubstringWithEnclave`

---

## 7. Configure the .NET Console App

### 7a. Update the connection string

Open `src/AlwaysEncryptPOC.Console/appsettings.json` and replace `<YOUR_SERVER>` with the `sqlServerFqdn` from Step 4:

```json
{
  "ConnectionStrings": {
    "SqlDatabase": "Server=sql-ae-poc-abc123.database.windows.net; Database=AlwaysEncryptPocDb; Column Encryption Setting=Enabled; Attestation Protocol=None;"
  }
}
```

**Connection string breakdown:**

| Setting | Value | Why |
|---|---|---|
| `Server` | Your SQL Server FQDN | Target server |
| `Database` | `AlwaysEncryptPocDb` | Target database |
| `Column Encryption Setting` | `Enabled` | Tells the driver to auto-encrypt/decrypt parameterized queries against AE columns |
| `Attestation Protocol` | `None` | VBS enclaves on Azure SQL Database use no attestation |

> **Note**: There is no username/password. The app uses `DefaultAzureCredential` which picks up your Azure CLI login to authenticate to both SQL and Key Vault.

### 7b. Ensure you're logged into Azure CLI

The console app uses `DefaultAzureCredential` for:
- **SQL authentication**: Gets an Azure AD token for the SQL Server
- **Key Vault access**: Unwraps Column Encryption Keys via the RSA keys in Key Vault

```powershell
az login
az account set --subscription "15442e45-facf-4f45-9d12-a54f479bc10f"
```

### 7c. Verify the build

```powershell
cd c:\source\AlwaysEncryptPOC
dotnet build
```

Should output: `Build succeeded` with 0 errors.

---

## 8. Run the Console App

```powershell
cd c:\source\AlwaysEncryptPOC\src\AlwaysEncryptPOC.Console
dotnet run
```

The app will:
1. Register the Azure Key Vault provider for Always Encrypted
2. Seed 5 rows into each of the 3 source tables (PlainData, EncryptedNoEnclave, EncryptedWithEnclave)
3. Run all 7 tests sequentially with console output

**Expected runtime:** 15–30 seconds (first run may take longer as the driver caches encryption metadata).

---

## 9. Expected Results

### Test 1 — Retrieve data from all 3 tables

**Expected**: All three tables return identical decrypted values. This proves the Always Encrypted driver transparently decrypts encrypted columns.

```
=== Test 1: Retrieve Data from All Tables ===

--- PlainData ---
  Id=1  SSN=795-73-9838  FullName=Catherine Abel      Salary=31692.00
  Id=2  SSN=990-00-6818  FullName=Kim Abercrombie      Salary=55415.00
  ...

--- EncryptedNoEnclave ---
  Id=1  SSN=795-73-9838  FullName=Catherine Abel      Salary=31692.00
  ...

--- EncryptedWithEnclave ---
  Id=1  SSN=795-73-9838  FullName=Catherine Abel      Salary=31692.00
  ...
```

### Test 2 — Move encrypted data (no enclave) via stored procedure

**Expected**: Succeeds. The stored procedure copies raw ciphertext from `EncryptedNoEnclave` to `EncryptedNoEnclave_Target` because both tables use the same CEK. The server doesn't need to decrypt anything.

### Test 3 — Move encrypted data (with enclave) via stored procedure

**Expected**: Succeeds. Same pattern for enclave tables.

### Test 4 — SUBSTRING on non-enclave data (EXPECTED FAILURE)

**Expected**: The stored procedure `usp_SubstringNoEnclave` fails with a `SqlException`:

```
=== Test 4: SUBSTRING on Non-Enclave Data ===

EXPECTED ERROR: Operand type clash: char(11) encrypted with
(encryption_type = 'DETERMINISTIC', ...) is incompatible with char
>> SUBSTRING is not supported on encrypted columns without an enclave.
```

**Why it fails**: Without a VBS enclave, the SQL Server cannot decrypt the ciphertext to perform the SUBSTRING operation. This is a fundamental limitation of standard Always Encrypted.

### Test 5 — SUBSTRING on enclave data (SUCCEEDS)

**Expected**: The VBS enclave decrypts the data in a protected memory area, performs SUBSTRING, and returns the result.

```
=== Test 5: SUBSTRING on Enclave Data ===

  Id=1  SSN_Prefix=795  Name_Prefix=Cathe
  Id=2  SSN_Prefix=990  Name_Prefix=Kim A
  ...
```

**Why it works**: The enclave-enabled CMK allows the SQL Server's VBS enclave to decrypt, compute, and re-encrypt — all within the secure enclave boundary.

### Test 6 — Update encrypted field

**Expected**: Both tables successfully update the Salary column. The driver encrypts the new parameter value client-side before sending to the server.

```
=== Test 6: Update Encrypted Field ===

  Updating Salary for Id=1 in EncryptedNoEnclave to 99999.00...
  Updated. Re-read: Id=1  Salary=99999.00 ✓

  Updating Salary for Id=1 in EncryptedWithEnclave to 99999.00...
  Updated. Re-read: Id=1  Salary=99999.00 ✓
```

### Test 7 — Equality queries on encrypted fields

| Sub-test | Query | Encryption Type | Enclave? | Expected |
|---|---|---|---|---|
| **7a** | `WHERE SSN = @ssn` on `EncryptedNoEnclave` | Deterministic | No | **Succeeds** — deterministic produces consistent ciphertext, so equality matching works |
| **7b** | `WHERE SSN = @ssn` on `EncryptedWithEnclave` | Deterministic | Yes | **Succeeds** |
| **7c** | `WHERE FullName = @name` on `EncryptedNoEnclave` | Randomized | No | **FAILS** — randomized encryption produces different ciphertext each time, so equality is impossible without an enclave |
| **7d** | `WHERE FullName = @name` on `EncryptedWithEnclave` | Randomized | Yes | **Succeeds** — the enclave decrypts both sides to compare |

```
=== Test 7c: Equality on Randomized (No Enclave) ===

EXPECTED ERROR: Encryption scheme mismatch for columns/variables '@name'...
>> Equality on randomized column is not supported without an enclave.
```

---

## 10. Cleanup

### 10a. Remove SQL objects (optional — if you want to reset the database)

In SSMS, open and execute `sql/05-Cleanup.sql`. This drops all POC objects in reverse dependency order:
1. Stored procedures
2. Target tables
3. Source tables
4. Column Encryption Keys
5. Column Master Keys

### 10b. Delete all Azure resources

```powershell
az group delete --name rg-alwaysencrypt-poc --yes --no-wait
```

This deletes the resource group and all resources inside it (Key Vault, SQL Server, Database).

> **Note**: The Key Vault has soft-delete and purge protection enabled. After deletion, the vault will remain in "soft deleted" state for 7 days. To permanently purge it:
> ```powershell
> az keyvault purge --name <keyVaultName>
> ```

---

## 11. Troubleshooting

### "Login failed" when running the console app

**Cause**: `DefaultAzureCredential` couldn't get a token for SQL.

**Fix**: Ensure you're logged into Azure CLI with the same account that's set as the SQL Azure AD admin:
```powershell
az login
az account show --query user.name -o tsv
```
The output should match your `principalName`.

### "Failed to decrypt a column encryption key" / Key Vault access denied

**Cause**: Your Azure AD identity doesn't have the required Key Vault RBAC role.

**Fix**: Verify roles are assigned:
```powershell
az role assignment list --scope "/subscriptions/15442e45-facf-4f45-9d12-a54f479bc10f/resourceGroups/rg-alwaysencrypt-poc/providers/Microsoft.KeyVault/vaults/<keyVaultName>" --output table
```
You should see both **Key Vault Crypto Officer** and **Key Vault Crypto User** for your principal ID.

### SSMS can't find Key Vault keys when creating CMK

**Cause**: You're not signed into Azure in SSMS, or the Key Vault names aren't visible.

**Fix**:
1. In the New Column Master Key dialog, click **Sign In** and use the same Azure AD account.
2. Verify the Key Vault exists: `az keyvault list --resource-group rg-alwaysencrypt-poc --output table`

### "Cannot connect to SQL Server" from SSMS or the app

**Cause**: Firewall rule doesn't include your IP.

**Fix**: Check if your IP has changed since deployment:
```powershell
(Invoke-WebRequest -Uri https://api.ipify.org).Content
```
If it changed, update the firewall:
```powershell
az sql server firewall-rule update `
  --resource-group rg-alwaysencrypt-poc `
  --server <sql-server-name> `
  --name AllowClientIP `
  --start-ip-address <new-ip> `
  --end-ip-address <new-ip>
```

### Test 4 or 7c doesn't fail (no error thrown)

**Cause**: The CMK for the non-enclave tables might have been accidentally created with "Allow enclave computations" checked.

**Fix**: In SSMS, check the CMK properties:
```sql
SELECT name, allow_enclave_computations FROM sys.column_master_keys;
```
`CMK_NoEnclave` should show `allow_enclave_computations = 0`. If it's `1`, drop and recreate the keys (run `sql/05-Cleanup.sql` first, then redo Steps 5 and 6).

### Build fails with "The type or namespace 'AlwaysEncrypted' does not exist"

**Cause**: The separate NuGet package for the AKV provider is missing.

**Fix**:
```powershell
cd src\AlwaysEncryptPOC.Console
dotnet add package Microsoft.Data.SqlClient.AlwaysEncrypted.AzureKeyVaultProvider
dotnet build
```

---

## Quick Reference: Step-by-Step Summary

| # | Step | Where | Manual? |
|---|---|---|---|
| 1 | Install prerequisites | Local machine | One-time setup |
| 2 | Gather principalId, principalName, clientIpAddress | PowerShell | Yes |
| 3 | Update `infra/main.bicepparam` with values | Editor | Yes |
| 4 | Run `az deployment sub create` | PowerShell | CLI command |
| 5 | Note deployment outputs (FQDN, key vault name) | PowerShell | CLI command |
| 6 | Create CMK_NoEnclave in SSMS (no enclave) | SSMS | **Manual — wizard** |
| 7 | Create CMK_WithEnclave in SSMS (with enclave) | SSMS | **Manual — wizard** |
| 8 | Create CEK_NoEnclave in SSMS | SSMS | **Manual — wizard** |
| 9 | Create CEK_WithEnclave in SSMS | SSMS | **Manual — wizard** |
| 10 | Run `sql/03-CreateTables.sql` | SSMS | Execute script |
| 11 | Run `sql/04-StoredProcedures.sql` | SSMS | Execute script |
| 12 | Update connection string in `appsettings.json` | Editor | Yes |
| 13 | Run `dotnet run` | PowerShell | CLI command |
| 14 | Review test output | Console | Read results |
