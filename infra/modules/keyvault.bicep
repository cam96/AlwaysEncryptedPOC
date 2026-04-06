@description('Azure region for all resources.')
param location string

@description('Azure AD Object ID of the developer (for RBAC role assignments).')
param principalId string

@description('Unique suffix for globally unique resource names.')
param uniqueSuffix string

// ---------------------------------------------------------------------------
// Key Vault — Standard SKU, RBAC authorization, soft-delete + purge protection
// ---------------------------------------------------------------------------
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: 'kv-ae-poc-${uniqueSuffix}'
  location: location
  properties: {
    tenantId: tenant().tenantId
    sku: {
      family: 'A'
      name: 'standard' // Standard is sufficient — HSM not needed for this POC
    }
    enableRbacAuthorization: true // Use Azure RBAC instead of access policies
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    enablePurgeProtection: true // Required — Always Encrypted keys must not be permanently deleted accidentally
    publicNetworkAccess: 'Enabled'
  }
}

// ---------------------------------------------------------------------------
// RSA 4096-bit Keys for Column Master Keys
// ---------------------------------------------------------------------------
resource cmkNoEnclaveKey 'Microsoft.KeyVault/vaults/keys@2023-07-01' = {
  parent: keyVault
  name: 'CMK-NoEnclave'
  properties: {
    kty: 'RSA'
    keySize: 4096 // 4096-bit entropy as required
    keyOps: [
      'wrapKey'
      'unwrapKey'
      'sign'
      'verify'
    ]
    attributes: {
      enabled: true
    }
  }
}

resource cmkWithEnclaveKey 'Microsoft.KeyVault/vaults/keys@2023-07-01' = {
  parent: keyVault
  name: 'CMK-WithEnclave'
  properties: {
    kty: 'RSA'
    keySize: 4096 // 4096-bit entropy as required
    keyOps: [
      'wrapKey'
      'unwrapKey'
      'sign'
      'verify'
    ]
    attributes: {
      enabled: true
    }
  }
}

// ---------------------------------------------------------------------------
// RBAC Role Assignments on the Key Vault
// ---------------------------------------------------------------------------

// Key Vault Crypto Officer — needed during SSMS key provisioning (sign for enclave signatures)
var kvCryptoOfficerRoleId = '14b46e9e-c2b7-41b4-b07b-48a6ebf60603'

resource roleAssignmentCryptoOfficer 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, principalId, kvCryptoOfficerRoleId)
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', kvCryptoOfficerRoleId)
    principalId: principalId
    principalType: 'User'
  }
}

// Key Vault Crypto User — needed at runtime by the .NET console app (unwrapKey/wrapKey for AE)
var kvCryptoUserRoleId = '12338af0-0e69-4776-bea7-57ae8d297424'

resource roleAssignmentCryptoUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, principalId, kvCryptoUserRoleId)
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', kvCryptoUserRoleId)
    principalId: principalId
    principalType: 'User'
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------
output keyVaultName string = keyVault.name
output keyVaultUri string = keyVault.properties.vaultUri
output cmkNoEnclaveKeyUri string = cmkNoEnclaveKey.properties.keyUriWithVersion
output cmkWithEnclaveKeyUri string = cmkWithEnclaveKey.properties.keyUriWithVersion
output cmkNoEnclaveKeyName string = cmkNoEnclaveKey.name
output cmkWithEnclaveKeyName string = cmkWithEnclaveKey.name
