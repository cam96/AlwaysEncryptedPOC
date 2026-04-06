# Plan: Azure SQL Always Encrypted POC

## TL;DR
Build Bicep IaC + .NET 10 console app + SQL scripts to demonstrate Azure SQL Always Encrypted across three scenarios: no encryption, encryption without enclaves, and encryption with VBS enclaves. Bicep provisions all Azure infrastructure (Key Vault with RSA 4096 keys, SQL Server with VBS enclave database, RBAC role assignments). The POC proves that rich computations (SUBSTRING) and data movement behave differently depending on enclave availability.

**Subscription**: Visual Studio Enterprise Subscription (`15442e45-facf-4f45-9d12-a54f479bc10f`)

---

## Project Structure

```
c:\source\AlwaysEncryptPOC\
├── AlwaysEncryptPOC.sln
├── infra\
│   ├── main.bicep                  -- subscription-level deployment (creates RG + modules)
│   ├── main.bicepparam             -- parameter values
│   └── modules\
│       ├── keyvault.bicep          -- Key Vault + RSA 4096 keys + RBAC role assignments
│       └── sql.bicep               -- SQL Server (AAD-only) + Database (VBS enclave) + firewall
├── src\
│   └── AlwaysEncryptPOC.Console\
│       ├── AlwaysEncryptPOC.Console.csproj
│       ├── Program.cs
│       ├── DataTests.cs
│       └── appsettings.json
├── sql\
│   ├── 01-CreateColumnMasterKeys.sql
│   ├── 02-CreateColumnEncryptionKeys.sql
│   ├── 03-CreateTables.sql
│   ├── 04-StoredProcedures.sql
│   └── 05-Cleanup.sql
└── README.md
```

---

## Decisions

- **Subscription**: `15442e45-facf-4f45-9d12-a54f479bc10f` (Visual Studio Enterprise Subscription)
- **Resource Group**: `rg-alwaysencrypt-poc` (created by Bicep at subscription scope)
- **CMK Store**: Azure Key Vault with RBAC authorization model (no access policies)
- **Enclave type**: VBS — `preferredEnclaveType: 'VBS'` on database, connection string uses `Attestation Protocol=None`
- **SQL Auth**: Azure AD-only authentication (`azureADOnlyAuthentication: true`) — no SQL admin password
- **Encryption types**: Deterministic (for SSN — allows equality) + Randomized (for FullName, Salary — stronger security)
- **Data insertion for encrypted tables**: Parameterized queries from .NET app (required by Always Encrypted)
- **Test 4 expected failure**: SUBSTRING on non-enclave encrypted column will throw — caught and displayed gracefully
- **.NET 10**: TFM `net10.0`

---

## Phase 0: Bicep Infrastructure

### Step 1 — Subscription-level deployment (`infra/main.bicep`)

Deploys at subscription scope. Creates the resource group, then deploys Key Vault and SQL modules into it.

**Parameters** (defined in `main.bicepparam`):
| Parameter | Type | Description |
|---|---|---|
| `location` | string | Azure region (default: `canadacentral`) |
| `principalId` | string | Azure AD Object ID of the developer running the console app & SSMS |
| `principalName` | string | Display name / UPN of the developer (used as SQL Azure AD admin login) |
| `clientIpAddress` | string | Developer's public IP for SQL firewall rule |

**Resources in main.bicep:**
- `Microsoft.Resources/resourceGroups` → `rg-alwaysencrypt-poc`
- Module reference to `modules/keyvault.bicep`
- Module reference to `modules/sql.bicep`
- Outputs: Key Vault name, Key Vault URI, SQL Server FQDN, Database name, Key URIs for both CMKs

### Step 2 — Key Vault module (`infra/modules/keyvault.bicep`)

| Resource | Type | Details |
|---|---|---|
| Key Vault | `Microsoft.KeyVault/vaults` | **SKU: standard**, RBAC authorization (`enableRbacAuthorization: true`), soft delete enabled, purge protection enabled, `tenantId: tenant().tenantId` |
| CMK-NoEnclave key | `Microsoft.KeyVault/vaults/keys` | **RSA 4096-bit** (`kty: 'RSA'`, `keySize: 4096`), `keyOps: ['wrapKey', 'unwrapKey', 'sign', 'verify']` |
| CMK-WithEnclave key | `Microsoft.KeyVault/vaults/keys` | **RSA 4096-bit** (`kty: 'RSA'`, `keySize: 4096`), `keyOps: ['wrapKey', 'unwrapKey', 'sign', 'verify']` |
| Role: Key Vault Crypto Officer | `Microsoft.Authorization/roleAssignments` | Role ID `14b46e9e-c2b7-41b4-b07b-48a6ebf60603` → assigned to `principalId`. **Needed for**: creating CMK/CEK metadata via SSMS (sign, verify for enclave signature generation) |
| Role: Key Vault Crypto User | `Microsoft.Authorization/roleAssignments` | Role ID `12338af0-0e69-4776-bea7-57ae8d297424` → assigned to `principalId`. **Needed for**: console app runtime AE operations (wrapKey, unwrapKey to encrypt/decrypt CEK) |

**Why both roles?**
- **Crypto Officer**: Required during SSMS key provisioning — needs `sign` permission to generate the enclave computation signature for `CMK_WithEnclave`, plus full key management
- **Crypto User**: Minimum required at runtime by the .NET console app for Always Encrypted operations (unwrapKey to decrypt the CEK). Assigned separately so it can be moved to a managed identity later

### Step 3 — SQL module (`infra/modules/sql.bicep`)

| Resource | Type | Details |
|---|---|---|
| SQL Logical Server | `Microsoft.Sql/servers` | **Azure AD-only auth** (`azureADOnlyAuthentication: true`), developer set as Azure AD admin via `administrators` property, `minimalTlsVersion: '1.2'`, `publicNetworkAccess: 'Enabled'` |
| SQL Database | `Microsoft.Sql/servers/databases` | **SKU: GP_Gen5_2** (General Purpose, Gen5, 2 vCores), `preferredEnclaveType: 'VBS'`, `requestedBackupStorageRedundancy: 'Local'`, `maxSizeBytes: 2147483648` (2 GB) |
| Firewall: Client IP | `Microsoft.Sql/servers/firewallRules` | `startIpAddress` / `endIpAddress` = `clientIpAddress` parameter |
| Firewall: Azure Services | `Microsoft.Sql/servers/firewallRules` | `0.0.0.0` → `0.0.0.0` (allows Azure services) |

**Tier justification:**
- **GP_Gen5_2** (General Purpose, vCore model, Gen5 hardware, 2 vCores): Cheapest vCore tier that supports VBS enclaves. DTU-based tiers do NOT support enclaves. Cost ~$XXX/mo under VS Enterprise benefit.
- **Standard SKU Key Vault**: Sufficient — HSM-backed keys (premium) not required for this POC. Standard supports RSA 4096 software-protected keys.

### Step 4 — Parameters file (`infra/main.bicepparam`)
- Uses `using './main.bicep'` syntax
- Placeholder values with comments for the developer to fill in `principalId`, `principalName`, `clientIpAddress`

### Deployment command
```
az deployment sub create \
  --name AlwaysEncryptPOC \
  --location canadacentral \
  --subscription 15442e45-facf-4f45-9d12-a54f479bc10f \
  --template-file infra/main.bicep \
  --parameters infra/main.bicepparam
```

---

## Phase 1: SQL Scripts *(depends on Phase 0 — infra must be deployed first)*

### Step 5 — Create Column Master Key scripts (`sql/01-CreateColumnMasterKeys.sql`)
- `CMK_NoEnclave`: Standard CMK, `KEY_STORE_PROVIDER_NAME = 'AZURE_KEY_VAULT'`, `KEY_PATH` = AKV key URI output from Bicep
- `CMK_WithEnclave`: Enclave-enabled CMK with `ENCLAVE_COMPUTATIONS (SIGNATURE = <hex>)` clause — signature placeholder must be generated by SSMS or PowerShell
- Both point to RSA 4096-bit keys already created by Bicep in Key Vault
- Script includes placeholder comments and instructions for filling in actual values

### Step 6 — Create Column Encryption Key scripts (`sql/02-CreateColumnEncryptionKeys.sql`)
- `CEK_NoEnclave`: Encrypted by `CMK_NoEnclave`
- `CEK_WithEnclave`: Encrypted by `CMK_WithEnclave`
- `ENCRYPTED_VALUE` placeholders — generated during provisioning via SSMS wizard
- Algorithm: `RSA_OAEP`

### Step 7 — Create Tables (`sql/03-CreateTables.sql`)

**Source tables (3):**
| Table | Columns | Encryption |
|---|---|---|
| `dbo.PlainData` | Id (int PK IDENTITY), SSN (char(11)), FullName (nvarchar(100)), Salary (money) | None |
| `dbo.EncryptedNoEnclave` | Same schema | SSN: Deterministic/CEK_NoEnclave, FullName: Randomized/CEK_NoEnclave, Salary: Randomized/CEK_NoEnclave |
| `dbo.EncryptedWithEnclave` | Same schema | SSN: Deterministic/CEK_WithEnclave, FullName: Randomized/CEK_WithEnclave, Salary: Randomized/CEK_WithEnclave |

**Target tables (2)** — for data movement tests:
| Table | Encryption |
|---|---|
| `dbo.EncryptedNoEnclave_Target` | Same column encryption as source (same CEK_NoEnclave) |
| `dbo.EncryptedWithEnclave_Target` | Same column encryption as source (same CEK_WithEnclave) |

### Step 8 — Stored Procedures (`sql/04-StoredProcedures.sql`)
- `dbo.usp_MoveEncryptedNoEnclaveData`: `INSERT INTO EncryptedNoEnclave_Target SELECT ... FROM EncryptedNoEnclave` — succeeds (same CEK, ciphertext copy)
- `dbo.usp_MoveEncryptedWithEnclaveData`: `INSERT INTO EncryptedWithEnclave_Target SELECT ... FROM EncryptedWithEnclave` — succeeds
- `dbo.usp_SubstringNoEnclave`: `SELECT Id, SUBSTRING(SSN, 1, 3) FROM EncryptedNoEnclave` — **will fail** (no enclave)
- `dbo.usp_SubstringWithEnclave`: `SELECT Id, SUBSTRING(SSN, 1, 3), SUBSTRING(FullName, 1, 5) FROM EncryptedWithEnclave` — **succeeds** (enclave decrypts in-place). Includes both deterministic (SSN) and randomized (FullName) columns.

### Step 9 — Cleanup script (`sql/05-Cleanup.sql`)
- DROP procedures, tables, CEKs, CMKs in dependency order

---

## Phase 2: .NET Console Application *(parallel with Phase 1)*

### Step 10 — Project scaffold
- Create solution `AlwaysEncryptPOC.sln`
- Create console project `src/AlwaysEncryptPOC.Console/AlwaysEncryptPOC.Console.csproj` targeting `net10.0`
- NuGet packages:
  - `Microsoft.Data.SqlClient` (latest — supports AE + VBS enclaves + AKV provider)
  - `Azure.Identity` (for `DefaultAzureCredential` — AKV + SQL auth)
  - `Microsoft.Extensions.Configuration`
  - `Microsoft.Extensions.Configuration.Json`
  - `Microsoft.Extensions.Configuration.UserSecrets`

### Step 11 — Configuration (`appsettings.json`)
- Connection string: `Server=<server>.database.windows.net; Database=AlwaysEncryptPocDb; Column Encryption Setting=Enabled; Attestation Protocol=None;`
- Auth via `DefaultAzureCredential` (Azure CLI login works locally)

### Step 12 — Data seeding (`DataTests.cs`)
- Parameterized inserts for all 3 source tables (driver auto-encrypts for AE columns)
- 3–5 sample rows with SSN, FullName, Salary

### Step 13 — Test implementations (`DataTests.cs`)

| Test | Action | Expected |
|---|---|---|
| 1. Retrieve all 3 ways | `SELECT *` from all 3 tables, display decrypted results | Transparent decryption by driver |
| 2. Move non-enclave data | `EXEC usp_MoveEncryptedNoEnclaveData`, verify target | Ciphertext copied successfully |
| 3. Move enclave data | `EXEC usp_MoveEncryptedWithEnclaveData`, verify target | Data moved successfully |
| 4. SUBSTRING non-enclave | `EXEC usp_SubstringNoEnclave`, catch `SqlException` | **Error displayed** — not supported |
| 5. SUBSTRING with enclave | `EXEC usp_SubstringWithEnclave`, display results | SSN prefixes + FullName prefixes returned |
| 6. Update encrypted field | Parameterized `UPDATE SET Salary WHERE Id` on both tables | Both succeed — driver encrypts parameter |
| 7a. Equality on deterministic (no enclave) | `SELECT WHERE SSN = @ssn` on `EncryptedNoEnclave` | **Succeeds** — ciphertext equality |
| 7b. Equality on deterministic (enclave) | `SELECT WHERE SSN = @ssn` on `EncryptedWithEnclave` | **Succeeds** |
| 7c. Equality on randomized (no enclave) | `SELECT WHERE FullName = @name` on `EncryptedNoEnclave` | **Fails** — `SqlException` |
| 7d. Equality on randomized (enclave) | `SELECT WHERE FullName = @name` on `EncryptedWithEnclave` | **Succeeds** — enclave decrypts to compare |

### Step 14 — Additional test implementations (`DataTests.cs`)

**Test 6 — Update a row using an encrypted field:**
- Execute parameterized `UPDATE EncryptedNoEnclave SET Salary = @newSalary WHERE Id = @id` from .NET app (driver encrypts `@newSalary`)
- Execute same on `EncryptedWithEnclave`
- Re-read both rows to verify updated value displayed in console
- Both succeed — demonstrates the driver transparently encrypts update parameters

**Test 7 — Equality query on encrypted field:**
- **7a**: `SELECT * FROM EncryptedNoEnclave WHERE SSN = @ssn` (deterministic, no enclave) → **succeeds** (ciphertext equality match)
- **7b**: `SELECT * FROM EncryptedWithEnclave WHERE SSN = @ssn` (deterministic, enclave) → **succeeds**
- **7c**: `SELECT * FROM EncryptedNoEnclave WHERE FullName = @name` (randomized, no enclave) → **fails** (`SqlException` — equality not supported on randomized without enclave). Catch and display error.
- **7d**: `SELECT * FROM EncryptedWithEnclave WHERE FullName = @name` (randomized, enclave) → **succeeds** (enclave decrypts to compare)

### Step 15 — Program.cs entry point
- Load configuration
- Register `SqlColumnEncryptionAzureKeyVaultProvider` with `DefaultAzureCredential`
- Register via `SqlConnection.RegisterColumnEncryptionKeyStoreProviders()`
- Run tests sequentially with clear console headers/separators

---

## Phase 3: Documentation

### Step 15 — README.md
- Prerequisites: Azure subscription, Azure CLI, .NET 10 SDK, SSMS
- Infrastructure deployment: `az deployment sub create` command with parameters
- Post-deployment: use SSMS to provision CMK/CEK (using AKV keys created by Bicep), then run SQL scripts 01-04
- How to run the console app
- Expected output for each test (including Test 4 failure)
- Cleanup: `az group delete` + `sql/05-Cleanup.sql`

---

## Permissions Summary

| Identity | Resource | Role / Permission | Purpose |
|---|---|---|---|
| Developer (principalId) | Key Vault | **Key Vault Crypto Officer** (`14b46e9e-c2b7-41b4-b07b-48a6ebf60603`) | SSMS provisioning: create CMK/CEK, sign enclave computation signature |
| Developer (principalId) | Key Vault | **Key Vault Crypto User** (`12338af0-0e69-4776-bea7-57ae8d297424`) | Console app runtime: unwrapKey/wrapKey for AE decrypt/encrypt CEK |
| Developer (principalId) | SQL Server | **Azure AD Admin** (set in Bicep `administrators` block) | Full database access — DDL, DML, SP execution. Implicitly `db_owner`. |
| Developer (principalId) | Subscription | **Contributor** (pre-existing) | Deploy Bicep infrastructure |

---

## Relevant Files

- `infra/main.bicep` — Subscription-level deployment, creates RG, invokes modules
- `infra/main.bicepparam` — Parameter values (principalId, principalName, clientIpAddress, location)
- `infra/modules/keyvault.bicep` — Key Vault (standard, RBAC), 2x RSA 4096 keys, 2x role assignments
- `infra/modules/sql.bicep` — SQL Server (AAD-only, TLS 1.2), Database (GP_Gen5_2, VBS enclave), firewall rules
- `sql/01-CreateColumnMasterKeys.sql` — CMK definitions referencing AKV key URIs
- `sql/02-CreateColumnEncryptionKeys.sql` — CEK definitions with encrypted value placeholders
- `sql/03-CreateTables.sql` — 5 tables (3 source + 2 target) with ENCRYPTED WITH clauses
- `sql/04-StoredProcedures.sql` — 4 stored procedures for data movement and SUBSTRING tests
- `sql/05-Cleanup.sql` — Reverse-order DROP statements
- `src/AlwaysEncryptPOC.Console/AlwaysEncryptPOC.Console.csproj` — .NET 10, NuGet refs
- `src/AlwaysEncryptPOC.Console/Program.cs` — Entry point, AKV provider registration, test orchestration
- `src/AlwaysEncryptPOC.Console/DataTests.cs` — Test methods + data seeding
- `src/AlwaysEncryptPOC.Console/appsettings.json` — Connection string with AE + attestation settings
- `README.md` — Full setup + run instructions + expected results

---

## Verification

1. **Bicep deployment**: `az deployment sub create` completes without errors; verify in portal that RG contains KV (with 2 keys) + SQL Server + Database (VBS enclave enabled)
2. **Build check**: `dotnet build` compiles without errors
3. **SQL script syntax**: Scripts parseable in SSMS without errors
4. **Test 1**: Console shows matching decrypted values across all 3 tables
5. **Tests 2 & 3**: Data present in target tables matching source
6. **Test 4**: Console displays `SqlException` about unsupported operations on encrypted columns
7. **Test 5**: Console displays SSN prefix substrings + FullName prefix substrings from enclave table
8. **Test 6**: Both tables show updated Salary value after re-read
9. **Test 7a/7b**: Both return rows matching the SSN filter (deterministic equality works everywhere)
10. **Test 7c**: Console displays `SqlException` — equality on randomized column unsupported without enclave
11. **Test 7d**: Returns row matching the FullName filter (randomized equality works with enclave)
12. **Security**: No secrets hardcoded — all in `appsettings.json` with placeholders, RBAC-only on Key Vault, AAD-only on SQL

---

## Further Considerations

1. **AKV key provisioning workflow**: Bicep creates the RSA 4096 keys in Key Vault. SSMS must then be used to create CMK/CEK metadata in SQL (wrapping key value, enclave signature). README will document this. Alternatively, a PowerShell script using `SqlServer` module could automate it. **Recommendation: README docs are sufficient for a POC.**

2. **SUBSTRING on Randomized columns**: Test 5 includes both SSN (deterministic) and FullName (randomized) to prove enclaves support rich computations on both encryption types.

3. **Cost awareness**: GP_Gen5_2 is the minimum vCore tier supporting VBS. Consider pausing/deleting resources when not testing. README will include cleanup instructions.
