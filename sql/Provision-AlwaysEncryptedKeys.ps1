<#
.SYNOPSIS
    Provisions Always Encrypted keys (CMK and CEK) in Azure SQL Database
    using Azure Key Vault. Scripted alternative to the SSMS wizard (Step 5).

.DESCRIPTION
    Creates the following metadata inside the target database:
      - CMK_NoEnclave   (Column Master Key, standard — no enclave computations)
      - CMK_WithEnclave  (Column Master Key, enclave-enabled with signed attestation)
      - CEK_NoEnclave   (Column Encryption Key, wrapped by CMK_NoEnclave)
      - CEK_WithEnclave  (Column Encryption Key, wrapped by CMK_WithEnclave)

    The SqlServer PowerShell module handles all cryptographic operations:
      - For CEKs: generates a random AES-256 symmetric key, wraps it with the
        RSA key in AKV (wrapKey operation), and stores the ciphertext in SQL metadata.
      - For the enclave CMK: signs the key path with the RSA private key in AKV
        (sign operation) to produce the ENCLAVE_COMPUTATIONS signature.

.PARAMETER SqlServerFqdn
    Fully qualified domain name of the Azure SQL Server
    (e.g., sql-ae-poc-abc123.database.windows.net).

.PARAMETER CmkNoEnclaveKeyUri
    Azure Key Vault key URI for CMK-NoEnclave
    (Bicep output: cmkNoEnclaveKeyUri).

.PARAMETER CmkWithEnclaveKeyUri
    Azure Key Vault key URI for CMK-WithEnclave
    (Bicep output: cmkWithEnclaveKeyUri).

.PARAMETER DatabaseName
    Target database name. Defaults to AlwaysEncryptPocDb.

.EXAMPLE
    # Get values from Bicep deployment outputs first:
    $outputs = az deployment sub show --name AlwaysEncryptPOC `
      --subscription 15442e45-facf-4f45-9d12-a54f479bc10f `
      --query properties.outputs -o json | ConvertFrom-Json

    .\sql\Provision-AlwaysEncryptedKeys.ps1 `
      -SqlServerFqdn $outputs.sqlServerFqdn.value `
      -CmkNoEnclaveKeyUri $outputs.cmkNoEnclaveKeyUri.value `
      -CmkWithEnclaveKeyUri $outputs.cmkWithEnclaveKeyUri.value
#>

[CmdletBinding()]
param(
    [string]$SqlServerFqdn = 'sql-ae-poc-xc4oppbqazkry.database.windows.net',

    [string]$CmkNoEnclaveKeyUri = 'https://kv-ae-poc-xc4oppbqazkry.vault.azure.net/keys/CMK-NoEnclave',

    [string]$CmkWithEnclaveKeyUri = 'https://kv-ae-poc-xc4oppbqazkry.vault.azure.net/keys/CMK-WithEnclave',

    [string]$DatabaseName = 'AlwaysEncryptPocDb'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── 1. Ensure required modules ───────────────────────────────────────────────
# Import SqlServer FIRST so its bundled Azure.Core assemblies load before
# Az.Accounts can load a conflicting version (avoids MissingMethodException).
foreach ($moduleName in @('SqlServer', 'Az.Accounts')) {
    if (-not (Get-Module -ListAvailable -Name $moduleName)) {
        Write-Host "Installing module $moduleName..."
        Install-Module -Name $moduleName -Force -AllowClobber -Scope CurrentUser
    }
    Import-Module $moduleName -Force
}

# ── 2. Authenticate ──────────────────────────────────────────────────────────
# Ensure we have an Azure context (for the SQL AAD token)
$azContext = Get-AzContext
if (-not $azContext) {
    Write-Host 'No Azure context found. Launching interactive login...'
    Connect-AzAccount -Tenant '3d8e5d74-1fba-458e-b12c-d2a157bccca6'
    Set-AzContext -Subscription '15442e45-facf-4f45-9d12-a54f479bc10f'
}

# ── 3. Connect to the database & obtain tokens ───────────────────────────────
Write-Host "`nConnecting to $SqlServerFqdn / $DatabaseName..."

# Get-AzAccessToken returns SecureString in modern Az.Accounts; convert to plain text.
function ConvertTo-PlainText([object]$token) {
    if ($token -is [System.Security.SecureString]) {
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($token)
        try { return [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
        finally { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
    }
    return [string]$token
}

$sqlToken = ConvertTo-PlainText (Get-AzAccessToken -ResourceUrl 'https://database.windows.net').Token
$database = Get-SqlDatabase -ServerInstance $SqlServerFqdn `
                            -Name $DatabaseName `
                            -AccessToken $sqlToken `
                            -Encrypt Optional

# Obtain an AKV access token for Always Encrypted operations (sign, wrapKey, unwrapKey).
# Passed directly to cmdlets instead of using Add-SqlAzureAuthenticationContext.
$kvToken = ConvertTo-PlainText (Get-AzAccessToken -ResourceUrl 'https://vault.azure.net').Token

# ── 4. Provision keys in a clean subprocess ───────────────────────────────────
# Az.Accounts and SqlServer ship conflicting versions of Azure.Core.dll.
# Running the Always Encrypted cmdlets in a child process that only loads
# SqlServer avoids the MissingMethodException.

$provisionScript = @'
param($ServerFqdn, $DbName, $SqlTok, $KvTok, $NoEnclaveUri, $WithEnclaveUri)
$ErrorActionPreference = 'Stop'
Import-Module SqlServer -Force

$db = Get-SqlDatabase -ServerInstance $ServerFqdn `
                      -Name $DbName `
                      -AccessToken $SqlTok `
                      -Encrypt Optional

# ── CMK_NoEnclave (standard, no enclave) ──
Write-Host 'Creating CMK_NoEnclave (standard, no enclave)...'
$cmkNo = New-SqlAzureKeyVaultColumnMasterKeySettings -KeyUrl $NoEnclaveUri
New-SqlColumnMasterKey -Name 'CMK_NoEnclave' `
                       -InputObject $db `
                       -ColumnMasterKeySettings $cmkNo

# ── CMK_WithEnclave (enclave-enabled) ──
Write-Host 'Creating CMK_WithEnclave (enclave-enabled)...'
$cmkEnc = New-SqlAzureKeyVaultColumnMasterKeySettings `
    -KeyUrl $WithEnclaveUri -AllowEnclaveComputations `
    -KeyVaultAccessToken $KvTok
New-SqlColumnMasterKey -Name 'CMK_WithEnclave' `
                       -InputObject $db `
                       -ColumnMasterKeySettings $cmkEnc

# ── CEK_NoEnclave ──
Write-Host 'Creating CEK_NoEnclave...'
New-SqlColumnEncryptionKey -Name 'CEK_NoEnclave' `
                           -InputObject $db `
                           -ColumnMasterKeyName 'CMK_NoEnclave' `
                           -KeyVaultAccessToken $KvTok

# ── CEK_WithEnclave ──
Write-Host 'Creating CEK_WithEnclave...'
New-SqlColumnEncryptionKey -Name 'CEK_WithEnclave' `
                           -InputObject $db `
                           -ColumnMasterKeyName 'CMK_WithEnclave' `
                           -KeyVaultAccessToken $KvTok
'@

$tempScript = Join-Path ([IO.Path]::GetTempPath()) 'Provision-AE-Keys-Sub.ps1'
Set-Content -Path $tempScript -Value $provisionScript -Encoding UTF8

try {
    Write-Host "`nProvisioning keys in clean subprocess (avoids Azure.Core conflict)..."
    & pwsh -NoProfile -File $tempScript `
        $SqlServerFqdn $DatabaseName $sqlToken $kvToken `
        $CmkNoEnclaveKeyUri $CmkWithEnclaveKeyUri
    if ($LASTEXITCODE -ne 0) { throw "Key provisioning subprocess failed (exit code $LASTEXITCODE)." }
}
finally {
    Remove-Item $tempScript -ErrorAction SilentlyContinue
}

# ── 5. Done ──────────────────────────────────────────────────────────────────
Write-Host "`nAll Always Encrypted keys provisioned successfully." -ForegroundColor Green
Write-Host "`nVerification queries (run in SSMS or sqlcmd):"
Write-Host '  SELECT name, allow_enclave_computations FROM sys.column_master_keys;'
Write-Host '  SELECT name, column_master_key_id FROM sys.column_encryption_keys;'
