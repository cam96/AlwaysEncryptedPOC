// ---------------------------------------------------------------------------
// Always Encrypted POC — Subscription-level Bicep deployment
// Creates resource group, Key Vault (with RSA 4096 keys), and Azure SQL
// (with VBS enclave database).
// ---------------------------------------------------------------------------
targetScope = 'subscription'

@description('Azure region for all resources.')
param location string = 'canadacentral' // Default to Canada Central, but can be overridden at deployment time

@description('Azure AD Object ID of the developer running SSMS and console app.')
param principalId string

@description('Display name or UPN of the developer (used as SQL Azure AD admin login).')
param principalName string

@description('Developer public IP address for SQL Server firewall rule.')
param clientIpAddress string

// Generate a deterministic unique suffix from the subscription ID for globally unique names
var uniqueSuffix = uniqueString(subscription().subscriptionId, 'alwaysencrypt-poc')

// ---------------------------------------------------------------------------
// Resource Group
// ---------------------------------------------------------------------------
resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: 'rg-alwaysencrypt-poc'
  location: location
}

// ---------------------------------------------------------------------------
// Key Vault Module — Standard SKU, RSA 4096 keys, RBAC role assignments
// ---------------------------------------------------------------------------
module keyVault 'modules/keyvault.bicep' = {
  name: 'keyVaultDeployment'
  scope: rg
  params: {
    location: location
    principalId: principalId
    uniqueSuffix: uniqueSuffix
  }
}

// ---------------------------------------------------------------------------
// SQL Module — Azure AD-only auth, GP_Gen5_2 with VBS enclave, firewall
// ---------------------------------------------------------------------------
module sql 'modules/sql.bicep' = {
  name: 'sqlDeployment'
  scope: rg
  params: {
    location: location
    principalId: principalId
    principalName: principalName
    clientIpAddress: clientIpAddress
    uniqueSuffix: uniqueSuffix
  }
}

// ---------------------------------------------------------------------------
// Outputs — use these to configure SQL scripts and appsettings.json
// ---------------------------------------------------------------------------
output resourceGroupName string = rg.name
output keyVaultName string = keyVault.outputs.keyVaultName
output keyVaultUri string = keyVault.outputs.keyVaultUri
output cmkNoEnclaveKeyUri string = keyVault.outputs.cmkNoEnclaveKeyUri
output cmkWithEnclaveKeyUri string = keyVault.outputs.cmkWithEnclaveKeyUri
output sqlServerFqdn string = sql.outputs.sqlServerFqdn
output databaseName string = sql.outputs.databaseName
