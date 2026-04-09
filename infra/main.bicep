targetScope = 'resourceGroup'

@minLength(1)
@maxLength(64)
@description('Name of the the environment which is used to generate a short unique hash used in all resources.')
param environmentName string

@minLength(1)
@description('Primary location for all resources')
@allowed([
  'northeurope'
  'uksouth'
  'swedencentral'
  'eastus'
  'eastus2'
  'southcentralus'
  'westus2'
  'westus3'
  'eastasia'
  'southeastasia'
  'australiaeast'
])
param location string

param burgerApiServiceName string = 'burger-api'
param burgerMcpServiceName string = 'burger-mcp'
param burgerWebappName string = 'burger-webapp'
param agentApiServiceName string = 'agent-api'
param agentWebappName string = 'agent-webapp'
param blobContainerName string = 'blobs'

@description('Location for the Static Web App')
@allowed(['westus2', 'centralus', 'eastus2', 'westeurope', 'eastasia'])
param webappLocation string = 'eastus2'

// Your existing Azure OpenAI endpoint and API key — required since we skip aiFoundry
@description('Your Azure OpenAI endpoint (required)')
param azureOpenAiAltEndpoint string

@description('Your Azure OpenAI API key (required)')
param azureOpenAiApiKey string

@description('The model deployment name on your Azure OpenAI resource')
param defaultModelName string

// Id of the user or app to assign application roles
param principalId string = ''

// Differentiates between automated and manual deployments
param isContinuousIntegration bool = false

// ---------------------------------------------------------------------------
// Common variables

var abbrs = loadJsonContent('abbreviations.json')
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))
var tags = { 'azd-env-name': environmentName }

var principalType = isContinuousIntegration ? 'ServicePrincipal' : 'User'
var burgerApiResourceName = '${abbrs.webSitesFunctions}burger-api-${resourceToken}'
var burgerMcpResourceName = '${abbrs.webSitesFunctions}burger-mcp-${resourceToken}'
var agentApiResourceName = '${abbrs.webSitesFunctions}agent-api-${resourceToken}'
var storageAccountName = '${abbrs.storageStorageAccounts}${resourceToken}'

// Use the provided Azure OpenAI endpoint directly
var openAiUrl = azureOpenAiAltEndpoint
var storageUrl = 'https://${storage.outputs.name}.blob.${environment().suffixes.storage}'
var burgerApiUrl = 'https://${burgerApiFunction.outputs.defaultHostname}'
var burgerMcpUrl = 'https://${burgerMcpFunction.outputs.defaultHostname}/mcp'
var burgerWebappUrl = 'https://${burgerWebapp.outputs.defaultHostname}'
var agentApiUrl = 'https://${agentApiFunction.outputs.defaultHostname}'
var agentWebappUrl = 'https://${agentWebapp.outputs.defaultHostname}'

// ---------------------------------------------------------------------------
// Resources

module burgerApiFunction 'br/public:avm/res/web/site:0.16.1' = {
  name: 'burger-api'
  params: {
    tags: union(tags, { 'azd-service-name': burgerApiServiceName })
    location: location
    kind: 'functionapp,linux'
    name: burgerApiResourceName
    serverFarmResourceId: burgerApiAppServicePlan.outputs.resourceId
    configs: [
      {
        name: 'appsettings'
        applicationInsightResourceId: appInsights.id
        storageAccountResourceId: storage.outputs.resourceId
        storageAccountUseIdentityAuthentication: true
      }
    ]
    managedIdentities: { systemAssigned: true }
    siteConfig: {
      minTlsVersion: '1.2'
      ftpsState: 'FtpsOnly'
      cors: {
        allowedOrigins: ['*']
        supportCredentials: false
      }
    }
    functionAppConfig: {
      deployment: {
        storage: {
          type: 'blobContainer'
          value: '${storage.outputs.primaryBlobEndpoint}${burgerApiResourceName}'
          authentication: {
            type: 'SystemAssignedIdentity'
          }
        }
      }
      scaleAndConcurrency: {
        alwaysReady: [
          {
            name: 'http'
            instanceCount: 1
          }
        ]
        maximumInstanceCount: 100
        instanceMemoryMB: 2048
      }
      runtime: {
        name: 'node'
        version: '22'
      }
    }
  }
}

module burgerApiFunctionSettings 'br/public:avm/res/web/site/config:0.1.0' = {
  name: 'burger-api-settings'
  params: {
    name: 'appsettings'
    appName: burgerApiFunction.outputs.name
    properties: {
      AZURE_STORAGE_URL: storageUrl
      AZURE_STORAGE_CONTAINER_NAME: blobContainerName
      AZURE_COSMOSDB_NOSQL_ENDPOINT: cosmosDb.outputs.endpoint
    }
    storageAccountResourceId: storage.outputs.resourceId
    storageAccountUseIdentityAuthentication: true
    applicationInsightResourceId: appInsights.id
  }
}

// Explicitly disable Easy Auth on burger-api
module burgerApiAuthDisable 'br/public:avm/res/web/site/config:0.1.0' = {
  name: 'burger-api-auth-disable'
  params: {
    name: 'authsettingsV2'
    appName: burgerApiFunction.outputs.name
    properties: {
      globalValidation: {
        requireAuthentication: false
        unauthenticatedClientAction: 'AllowAnonymous'
      }
      platform: {
        enabled: false
      }
    }
  }
}

module burgerApiAppServicePlan 'br/public:avm/res/web/serverfarm:0.4.1' = {
  name: 'burger-api-appserviceplan'
  params: {
    name: '${abbrs.webServerFarms}burger-api-${resourceToken}'
    tags: tags
    location: location
    skuName: 'FC1'
    reserved: true
  }
}

module burgerWebapp 'br/public:avm/res/web/static-site:0.9.3' = {
  name: 'burger-webapp'
  params: {
    name: burgerWebappName
    location: webappLocation
    tags: union(tags, { 'azd-service-name': burgerWebappName })
  }
}

module agentApiFunction 'br/public:avm/res/web/site:0.16.1' = {
  name: 'agent-api'
  params: {
    tags: union(tags, { 'azd-service-name': agentApiServiceName })
    location: location
    kind: 'functionapp,linux'
    name: agentApiResourceName
    serverFarmResourceId: agentApiAppServicePlan.outputs.resourceId
    configs: [
      {
        name: 'appsettings'
        applicationInsightResourceId: appInsights.id
        storageAccountResourceId: storage.outputs.resourceId
        storageAccountUseIdentityAuthentication: true
      }
    ]
    managedIdentities: { systemAssigned: true }
    siteConfig: {
      minTlsVersion: '1.2'
      ftpsState: 'FtpsOnly'
      cors: {
        allowedOrigins: ['*']
        supportCredentials: false
      }
    }
    functionAppConfig: {
      deployment: {
        storage: {
          type: 'blobContainer'
          value: '${storage.outputs.primaryBlobEndpoint}${agentApiResourceName}'
          authentication: {
            type: 'SystemAssignedIdentity'
          }
        }
      }
      scaleAndConcurrency: {
        alwaysReady: [
          {
            name: 'http'
            instanceCount: 1
          }
        ]
        maximumInstanceCount: 100
        instanceMemoryMB: 2048
      }
      runtime: {
        name: 'node'
        version: '22'
      }
    }
  }
}

module agentApiFunctionSettings 'br/public:avm/res/web/site/config:0.1.0' = {
  name: 'agent-api-settings'
  params: {
    name: 'appsettings'
    appName: agentApiFunction.outputs.name
    properties: {
      AZURE_COSMOSDB_NOSQL_ENDPOINT: cosmosDb.outputs.endpoint
      AZURE_OPENAI_API_ENDPOINT: openAiUrl
      AZURE_OPENAI_API_KEY: azureOpenAiApiKey
      AZURE_OPENAI_MODEL: defaultModelName
      BURGER_MCP_URL: burgerMcpUrl
    }
    storageAccountResourceId: storage.outputs.resourceId
    storageAccountUseIdentityAuthentication: true
    applicationInsightResourceId: appInsights.id
  }
}

module agentApiAppServicePlan 'br/public:avm/res/web/serverfarm:0.4.1' = {
  name: 'agent-api-appserviceplan'
  params: {
    name: '${abbrs.webServerFarms}agent-api-${resourceToken}'
    tags: tags
    location: location
    skuName: 'FC1'
    reserved: true
  }
}

module agentWebapp 'br/public:avm/res/web/static-site:0.9.3' = {
  name: 'agent-webapp'
  params: {
    name: agentWebappName
    location: webappLocation
    tags: union(tags, { 'azd-service-name': agentWebappName })
    sku: 'Standard'
    linkedBackend: {
      resourceId: agentApiFunction.outputs.resourceId
      location: location
    }
  }
}

module burgerMcpFunction 'br/public:avm/res/web/site:0.16.1' = {
  name: 'burger-mcp'
  params: {
    tags: union(tags, { 'azd-service-name': burgerMcpServiceName })
    location: location
    kind: 'functionapp,linux'
    name: burgerMcpResourceName
    serverFarmResourceId: burgerMcpAppServicePlan.outputs.resourceId
    configs: [
      {
        name: 'appsettings'
        applicationInsightResourceId: appInsights.id
        storageAccountResourceId: storage.outputs.resourceId
        storageAccountUseIdentityAuthentication: true
      }
    ]
    managedIdentities: { systemAssigned: true }
    siteConfig: {
      minTlsVersion: '1.2'
      ftpsState: 'FtpsOnly'
      cors: {
        allowedOrigins: ['*']
        supportCredentials: false
      }
    }
    functionAppConfig: {
      deployment: {
        storage: {
          type: 'blobContainer'
          value: '${storage.outputs.primaryBlobEndpoint}${burgerMcpResourceName}'
          authentication: {
            type: 'SystemAssignedIdentity'
          }
        }
      }
      scaleAndConcurrency: {
        alwaysReady: [
          {
            name: 'http'
            instanceCount: 1
          }
        ]
        maximumInstanceCount: 100
        instanceMemoryMB: 2048
      }
      runtime: {
        name: 'node'
        version: '22'
      }
    }
  }
}

module burgerMcpFunctionSettings 'br/public:avm/res/web/site/config:0.1.0' = {
  name: 'burger-mcp-settings'
  params: {
    name: 'appsettings'
    appName: burgerMcpFunction.outputs.name
    properties: {
      AzureWebJobsFeatureFlags: 'EnableMcpCustomHandlerPreview'
      AZURE_STORAGE_URL: storageUrl
      AZURE_STORAGE_CONTAINER_NAME: blobContainerName
      BURGER_API_URL: burgerApiUrl
    }
    storageAccountResourceId: storage.outputs.resourceId
    storageAccountUseIdentityAuthentication: true
    applicationInsightResourceId: appInsights.id
  }
}

module burgerMcpAppServicePlan 'br/public:avm/res/web/serverfarm:0.4.1' = {
  name: 'burger-mcp-appserviceplan'
  params: {
    name: '${abbrs.webServerFarms}burger-mcp-${resourceToken}'
    tags: tags
    location: location
    skuName: 'FC1'
    reserved: true
  }
}

module storage 'br/public:avm/res/storage/storage-account:0.26.2' = {
  name: 'storage'
  params: {
    name: storageAccountName
    tags: tags
    location: location
    skuName: 'Standard_LRS'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
    blobServices: {
      containers: [
        { name: burgerApiResourceName }
        { name: agentApiResourceName }
        { name: burgerMcpResourceName }
        {
          name: blobContainerName
          publicAccess: 'None'
        }
      ]
    }
    roleAssignments: [
      {
        principalId: principalId
        principalType: principalType
        roleDefinitionIdOrName: 'Storage Blob Data Contributor'
      }
    ]
  }
}

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: '${abbrs.operationalInsightsWorkspaces}${resourceToken}'
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: '${abbrs.insightsComponents}${resourceToken}'
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
  }
}

module cosmosDb 'br/public:avm/res/document-db/database-account:0.16.0' = {
  name: 'cosmosDb'
  params: {
    name: '${abbrs.documentDBDatabaseAccounts}${resourceToken}'
    tags: tags
    location: location
    zoneRedundant: false
    managedIdentities: {
      systemAssigned: true
    }
    capabilitiesToAdd: [
      'EnableServerless'
      'EnableNoSQLVectorSearch'
    ]
    networkRestrictions: {
      ipRules: []
      virtualNetworkRules: []
      publicNetworkAccess: 'Enabled'
    }
    sqlDatabases: [
      {
        containers: [
          { name: 'orders', paths: ['/id'] }
          { name: 'burgers', paths: ['/id'] }
          { name: 'toppings', paths: ['/id'] }
        ]
        name: 'burgerDB'
      }
      {
        containers: [
          { name: 'users', paths: ['/id'] }
        ]
        name: 'userDB'
      }
      {
        containers: [
          { name: 'history', paths: ['/userId'] }
        ]
        name: 'historyDB'
      }
    ]
    dataPlaneRoleDefinitions: [
      {
        roleName: 'db-contrib-role-definition'
        dataActions: [
          'Microsoft.DocumentDB/databaseAccounts/readMetadata'
          'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers/items/*'
          'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers/*'
        ]
        assignments: [
          { principalId: principalId }
          { principalId: burgerApiFunction.outputs.systemAssignedMIPrincipalId! }
          { principalId: agentApiFunction.outputs.systemAssignedMIPrincipalId! }
        ]
      }
    ]
  }
}

// ---------------------------------------------------------------------------
// System role assignments

module storageRoleBurgerApi 'br/public:avm/ptn/authorization/resource-role-assignment:0.1.2' = {
  name: 'storage-role-burger-api'
  params: {
    principalId: burgerApiFunction.outputs.systemAssignedMIPrincipalId!
    roleName: 'Storage Blob Data Contributor'
    roleDefinitionId: 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'
    resourceId: storage.outputs.resourceId
  }
}

module storageRoleAgentApi 'br/public:avm/ptn/authorization/resource-role-assignment:0.1.2' = {
  name: 'storage-role-agent-api'
  params: {
    principalId: agentApiFunction.outputs.systemAssignedMIPrincipalId!
    roleName: 'Storage Blob Data Contributor'
    roleDefinitionId: 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'
    resourceId: storage.outputs.resourceId
  }
}

module storageRoleBurgerMcp 'br/public:avm/ptn/authorization/resource-role-assignment:0.1.2' = {
  name: 'storage-role-burger-mcp'
  params: {
    principalId: burgerMcpFunction.outputs.systemAssignedMIPrincipalId!
    roleName: 'Storage Blob Data Contributor'
    roleDefinitionId: 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'
    resourceId: storage.outputs.resourceId
  }
}

// ---------------------------------------------------------------------------
// Outputs

output AZURE_LOCATION string = location
output AZURE_TENANT_ID string = tenant().tenantId

output BURGER_API_URL string = burgerApiUrl
output BURGER_MCP_URL string = burgerMcpUrl
output BURGER_WEBAPP_URL string = burgerWebappUrl
output AGENT_API_URL string = agentApiUrl
output AGENT_WEBAPP_URL string = agentWebappUrl

output AZURE_STORAGE_URL string = storageUrl
output AZURE_STORAGE_CONTAINER_NAME string = blobContainerName

output AZURE_COSMOSDB_NOSQL_ENDPOINT string = cosmosDb.outputs.endpoint

output AZURE_OPENAI_API_ENDPOINT string = openAiUrl
output AZURE_OPENAI_MODEL string = defaultModelName
