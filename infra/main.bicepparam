using './main.bicep'

// ---------------------------------------------------------------------------
// INSTRUCTIONS: Fill in the values below before deploying.
//
// Deploy with:
//   az deployment sub create `
//     --name AlwaysEncryptPOC `
//     --location canadacentral `
//     --subscription 15442e45-facf-4f45-9d12-a54f479bc10f `
//     --template-file infra/main.bicep `
//     --parameters infra/main.bicepparam
//
// To find your Azure AD Object ID:
//   az ad signed-in-user show --query id -o tsv
//
// To find your public IP:
//   (Invoke-WebRequest -Uri https://api.ipify.org).Content
// ---------------------------------------------------------------------------

param location = 'canadacentral'

// TODO: Replace with your Azure AD Object ID (run: az ad signed-in-user show --query id -o tsv)
param principalId = 'aawef93b5-8738-4c9a-81dd-399e1dd18708'

// TODO: Replace with your display name or UPN (run: az ad signed-in-user show --query userPrincipalName -o tsv)
param principalName = 'email'

// TODO: Replace with your public IP address (run: (Invoke-WebRequest -Uri https://api.ipify.org).Content)
param clientIpAddress = '203.0.113.42'
