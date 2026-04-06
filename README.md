# Always Encrypted POC — Azure SQL with VBS Enclaves

Proof of concept demonstrating Azure SQL Always Encrypted across three scenarios:
- **No encryption** (baseline)
- **Always Encrypted without enclaves** (standard AE)
- **Always Encrypted with VBS enclaves** (rich computations enabled)

## Prerequisites

- **Azure subscription**: Visual Studio Enterprise Subscription (`15442e45-facf-4f45-9d12-a54f479bc10f`)
- **Azure CLI** (`az`): [Install](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli)
- **.NET 9 SDK**: [Download](https://dotnet.microsoft.com/download/dotnet/9.0)
- **SSMS** (SQL Server Management Studio): [Download](https://learn.microsoft.com/en-us/sql/ssms/download-sql-server-management-studio-ssms)
- **Contributor** role on the subscription (to deploy Bicep)

## Architecture

### Azure Resources (deployed via Bicep)

| Resource | SKU / Tier | Why |
|---|---|---|
| **Resource Group** | `rg-alwaysencrypt-poc` | Container for all POC resources |
| **Key Vault** | Standard | RBAC auth; holds 2 RSA 4096-bit keys for Column Master Keys |
| **SQL Server** | Azure AD-only auth, TLS 1.2 | Logical server for the database |
| **SQL Database** | **GP_Gen5_2** (General Purpose, Gen5, 2 vCores) | Cheapest vCore tier supporting VBS enclaves. DTU tiers do NOT support enclaves. |

### Permissions Assigned by Bicep

| Identity | Resource | Role | Purpose |
|---|---|---|---|
| Developer | Key Vault | **Key Vault Crypto Officer** | SSMS: sign enclave computation signature, manage keys |
| Developer | Key Vault | **Key Vault Crypto User** | Console app: unwrapKey/wrapKey for AE CEK operations |
| Developer | SQL Server | **Azure AD Admin** | Full DB access (implicit db_owner) |

## Step 1: Deploy Infrastructure

1. Log in to Azure CLI:
   ```powershell
   az login
   az account set --subscription 15442e45-facf-4f45-9d12-a54f479bc10f
   ```

2. Get your Azure AD Object ID and public IP:
   ```powershell
   # Your Azure AD Object ID
   az ad signed-in-user show --query id -o tsv

   # Your UPN (login name for SQL Azure AD admin)
   az ad signed-in-user show --query userPrincipalName -o tsv

   # Your public IP
   (Invoke-WebRequest -Uri https://api.ipify.org).Content
   ```

3. Update `infra/main.bicepparam` with the values from step 2.

4. Deploy:
   ```powershell
   az deployment sub create `
     --name AlwaysEncryptPOC `
     --location canadacentral `
     --subscription 15442e45-facf-4f45-9d12-a54f479bc10f `
     --template-file infra/main.bicep `
     --parameters infra/main.bicepparam
   ```

5. Note the deployment outputs (Key Vault URI, key URIs, SQL Server FQDN, database name).

## Step 2: Provision Always Encrypted Keys via SSMS

Bicep creates the RSA 4096-bit keys in Key Vault, but the **Column Master Key (CMK)** and **Column Encryption Key (CEK)** metadata in SQL must be created via SSMS or PowerShell.

### Create CMK_NoEnclave (standard, no enclave)

1. In SSMS, connect to `AlwaysEncryptPocDb` with **Always Encrypted disabled**.
2. Expand **Security > Always Encrypted Keys > Column Master Keys**.
3. Right-click > **New Column Master Key...**
4. Name: `CMK_NoEnclave`
5. Key store: **Azure Key Vault** > sign in > select the key `CMK-NoEnclave`
6. **Uncheck** "Allow enclave computations"
7. Click OK.

### Create CMK_WithEnclave (enclave-enabled)

1. Same steps, but name: `CMK_WithEnclave`
2. Select key `CMK-WithEnclave`
3. **Check** "Allow enclave computations"
4. Click OK. SSMS will generate the enclave computation signature using the `sign` permission.

### Create CEK_NoEnclave

1. Right-click **Column Encryption Keys** > **New Column Encryption Key...**
2. Name: `CEK_NoEnclave`, select `CMK_NoEnclave`
3. Click OK.

### Create CEK_WithEnclave

1. Name: `CEK_WithEnclave`, select `CMK_WithEnclave`
2. Click OK.

## Step 3: Create Tables and Stored Procedures

In SSMS (connected to `AlwaysEncryptPocDb`), run these scripts in order:

1. `sql/03-CreateTables.sql` — Creates 5 tables (3 source + 2 target)
2. `sql/04-StoredProcedures.sql` — Creates 4 stored procedures

> **Note**: The `01` and `02` SQL scripts are reference documentation for what SSMS creates in Step 2. You don't need to run them manually if you used the SSMS wizard.

## Step 4: Configure and Run the Console App

1. Update `src/AlwaysEncryptPOC.Console/appsettings.json` with your SQL Server FQDN:
   ```json
   {
     "ConnectionStrings": {
       "SqlDatabase": "Server=sql-ae-poc-xxxxx.database.windows.net; Database=AlwaysEncryptPocDb; Column Encryption Setting=Enabled; Attestation Protocol=None;"
     }
   }
   ```

2. Ensure you're logged into Azure CLI (the app uses `DefaultAzureCredential`):
   ```powershell
   az login
   ```

3. Run the app:
   ```powershell
   cd src/AlwaysEncryptPOC.Console
   dotnet run
   ```

## Expected Output

### Test 1 — Retrieve data from all 3 tables
All tables return identical decrypted values. The driver transparently decrypts encrypted columns.

### Test 2 — Move encrypted data (no enclave) via SP
Ciphertext is copied from `EncryptedNoEnclave` to `EncryptedNoEnclave_Target` (same CEK). Succeeds.

### Test 3 — Move encrypted data (with enclave) via SP
Same pattern for enclave tables. Succeeds.

### Test 4 — SUBSTRING on non-enclave data (FAILS)
```
EXPECTED ERROR: Operand type clash: char(11) encrypted with (encryption_type = 'DETERMINISTIC', ...) 
is incompatible with char
>> SUBSTRING is not supported on encrypted columns without enclave.
```

### Test 5 — SUBSTRING on enclave data (SUCCEEDS)
Returns SSN prefixes and FullName prefixes computed inside the VBS enclave.

### Test 6 — Update encrypted field
Both tables successfully update the Salary column via parameterized UPDATE.

### Test 7 — Equality queries
- **7a**: `WHERE SSN = @ssn` on non-enclave deterministic — **succeeds** (ciphertext equality)
- **7b**: `WHERE SSN = @ssn` on enclave deterministic — **succeeds**
- **7c**: `WHERE FullName = @name` on non-enclave randomized — **FAILS** (randomized equality requires enclave)
- **7d**: `WHERE FullName = @name` on enclave randomized — **succeeds** (enclave decrypts to compare)

## Cleanup

1. Remove SQL objects:
   ```sql
   -- Run sql/05-Cleanup.sql in SSMS
   ```

2. Delete Azure resources:
   ```powershell
   az group delete --name rg-alwaysencrypt-poc --yes --no-wait
   ```

## Project Structure

```
├── infra/
│   ├── main.bicep              — Subscription-level deployment
│   ├── main.bicepparam         — Parameter values (fill in before deploying)
│   └── modules/
│       ├── keyvault.bicep      — Key Vault + RSA 4096 keys + RBAC
│       └── sql.bicep           — SQL Server + Database (VBS enclave) + firewall
├── src/AlwaysEncryptPOC.Console/
│   ├── Program.cs              — Entry point, AKV provider registration
│   ├── DataTests.cs            — All 7 tests + data seeding
│   └── appsettings.json        — Connection string (update before running)
├── sql/
│   ├── 01-CreateColumnMasterKeys.sql   — CMK reference scripts
│   ├── 02-CreateColumnEncryptionKeys.sql — CEK reference scripts
│   ├── 03-CreateTables.sql             — 5 tables
│   ├── 04-StoredProcedures.sql         — 4 stored procedures
│   └── 05-Cleanup.sql                  — Drop everything
└── README.md
```
