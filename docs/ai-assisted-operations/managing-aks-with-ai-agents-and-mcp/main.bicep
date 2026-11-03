var location = resourceGroup().location
var suffix = uniqueString(resourceGroup().id)
var aksName = 'aks-${suffix}'
var aiServicesName = 'ai-${suffix}'
var identityName = 'mi-${suffix}'

resource aks 'Microsoft.ContainerService/managedClusters@2026-01-02-preview' = {
  name: aksName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    dnsPrefix: aksName
    agentPoolProfiles: [
      {
        name: 'nodepool1'
        count: 3
        vmSize: 'standard_d2ds_v6'
        osType: 'Linux'
        mode: 'System'
        securityProfile: {
          sshAccess: 'Disabled'
        }
      }
    ]
    networkProfile: {
      networkPlugin: 'azure'
      networkPluginMode: 'overlay'
      networkDataplane: 'cilium'
      networkPolicy: 'cilium'
    }
    oidcIssuerProfile: {
      enabled: true
    }
    securityProfile: {
      workloadIdentity: {
        enabled: true
      }
    }
  }
}

resource aiServices 'Microsoft.CognitiveServices/accounts@2025-12-01' = {
  name: aiServicesName
  location: location
  kind: 'AIServices'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    customSubDomainName: aiServicesName
    publicNetworkAccess: 'Enabled'
  }
  sku: {
    name: 'S0'
  }
}

resource gpt5MiniDeployment 'Microsoft.CognitiveServices/accounts/deployments@2025-12-01' = {
  parent: aiServices
  name: 'gpt-5-mini'
  properties: {
    model: {
      format: 'OpenAI'
      name: 'gpt-5-mini'
      version: '2025-08-07'
    }
  }
  sku: {
    name: 'GlobalStandard'
    capacity: 500 // 1000 if you got it, 500 should be sufficient
  }
}

resource userAssignedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' = {
  name: identityName
  location: location
}

output rgName string = resourceGroup().name
output aksName string = aks.name
output aksOIDCIssuer string = aks.properties.oidcIssuerProfile.issuerUrl
output location string = location
output aiName string = aiServices.name
#disable-next-line outputs-should-not-contain-secrets
output aiApiKey string = aiServices.listKeys().key1
output aiApiBase string = aiServices.properties.endpoints['OpenAI Language Model Instance API']
output userAssignedIdentityName string = userAssignedIdentity.name
