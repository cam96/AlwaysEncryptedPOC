@description('Azure region for all resources.')
param location string

@description('Azure AD Object ID of the developer (SQL Azure AD admin).')
param principalId string

@description('Display name or UPN of the developer (SQL Azure AD admin login name).')
param principalName string

@description('Developer public IP address for SQL firewall rule.')
param clientIpAddress string

@description('Unique suffix for globally unique resource names.')
param uniqueSuffix string

// ---------------------------------------------------------------------------
// SQL Logical Server — Azure AD-only authentication, TLS 1.2
// ---------------------------------------------------------------------------
resource sqlServer 'Microsoft.Sql/servers@2023-08-01-preview' = {
  name: 'sql-ae-poc-${uniqueSuffix}'
  location: location
  properties: {
    minimalTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
    administrators: {
      administratorType: 'ActiveDirectory'
      login: principalName
      sid: principalId
      tenantId: tenant().tenantId
      azureADOnlyAuthentication: true // No SQL password — Azure AD only
    }
  }
}

// ---------------------------------------------------------------------------
// SQL Database — General Purpose Gen5 2 vCores, VBS enclave enabled
// ---------------------------------------------------------------------------
// GP_Gen5_2 is the cheapest vCore tier that supports VBS enclaves.
// DTU-based tiers do NOT support enclaves.
resource sqlDatabase 'Microsoft.Sql/servers/databases@2023-08-01-preview' = {
  parent: sqlServer
  name: 'AlwaysEncryptPocDb'
  location: location
  sku: {
    name: 'GP_Gen5'
    tier: 'GeneralPurpose'
    family: 'Gen5'
    capacity: 2 // 2 vCores — minimum for VBS enclave support
  }
  properties: {
    preferredEnclaveType: 'VBS' // Enable VBS secure enclaves
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    maxSizeBytes: 2147483648 // 2 GB — sufficient for POC
    requestedBackupStorageRedundancy: 'Local' // Cheapest backup option for POC
  }
}

// ---------------------------------------------------------------------------
// Firewall Rules
// ---------------------------------------------------------------------------

// Allow developer's client IP
resource firewallClientIp 'Microsoft.Sql/servers/firewallRules@2023-08-01-preview' = {
  parent: sqlServer
  name: 'AllowClientIP'
  properties: {
    startIpAddress: clientIpAddress
    endIpAddress: clientIpAddress
  }
}

// Allow Azure services (needed if running from Azure-hosted tools)
resource firewallAzureServices 'Microsoft.Sql/servers/firewallRules@2023-08-01-preview' = {
  parent: sqlServer
  name: 'AllowAzureServices'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------
output sqlServerName string = sqlServer.name
output sqlServerFqdn string = sqlServer.properties.fullyQualifiedDomainName
output databaseName string = sqlDatabase.name
