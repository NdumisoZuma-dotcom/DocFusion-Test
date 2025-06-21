// ==========================
// PARAMETERS
// ==========================

// Prefix for naming all resources (e.g., 'docfusion-dev')
@description('Prefix for naming resources')
@minLength(3)
param resourcePrefix string

// Azure region to deploy resources in; default is the resource group’s location
@description('Azure region to deploy resources')
param location string = resourceGroup().location

// IP or CIDR range that is allowed access on port 443 (HTTPS)
@description('Allowed public IP address or range for NSG rule')
param allowedIP string


// ==========================
// VIRTUAL NETWORK + SUBNET + NSG
// ==========================

// Create a virtual network with a /16 address space
resource vnet 'Microsoft.Network/virtualNetworks@2023-06-01' = {
  name: '${resourcePrefix}-vnet'  // VNet name: e.g., docfusion-dev-vnet
  location: location              // VNet location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'            // Define VNet address space
      ]
    }
    subnets: [
      {
        name: 'storageSubnet'    // Create a subnet named 'storageSubnet'
        properties: {
          addressPrefix: '10.0.1.0/24'  // Subnet address space
          networkSecurityGroup: {
            id: nsg.id           // Associate the NSG we define below to this subnet
          }
        }
      }
    ]
  }
}

// Define a Network Security Group (NSG) to control traffic to the subnet
resource nsg 'Microsoft.Network/networkSecurityGroups@2023-06-01' = {
  name: '${resourcePrefix}-nsg'   // NSG name
  location: location              // NSG location
  properties: {
    securityRules: [
      {
        name: 'Allow-HTTPS-From-AllowedIP' // Rule to allow HTTPS from specific IP
        properties: {
          priority: 100                     // Priority of the rule (lower = higher priority)
          direction: 'Inbound'              // Inbound traffic rule
          access: 'Allow'                   // Allow traffic
          protocol: 'Tcp'                   // For TCP protocol
          sourceAddressPrefix: allowedIP     // From the allowed IP
          sourcePortRange: '*'               // From any source port
          destinationAddressPrefix: '*'      // To any destination address
          destinationPortRange: '443'        // To HTTPS port
        }
      }
      {
        name: 'Deny-All-Inbound'             // Explicitly deny everything else inbound
        properties: {
          priority: 200                      // Lower priority than allow rule
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
    ]
  }
}


// ==========================
// STORAGE ACCOUNT
// ==========================

// Create a Storage Account (StorageV2, Standard_LRS)
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: toLower('${resourcePrefix}sa')      // Storage account name in lowercase
  location: location
  kind: 'StorageV2'                         // General-purpose v2 storage
  sku: {
    name: 'Standard_LRS'                    // Standard locally redundant storage
  }
  properties: {
    allowBlobPublicAccess: false            // Disable public blob access
    minimumTlsVersion: 'TLS1_2'             // Enforce TLS 1.2 for security
    networkAcls: {                          // Restrict network access
      defaultAction: 'Deny'                 // Deny by default
      bypass: 'AzureServices'               // Allow Azure services to bypass
      virtualNetworkRules: [                // Allow access from our subnet only
        {
          id: '${vnet.id}/subnets/storageSubnet'
        }
      ]
    }
  }
}


// ==========================
// APP SERVICE PLAN
// ==========================

// Create App Service Plan (B1 = Basic tier, cost-effective)
resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: '${resourcePrefix}-plan'
  location: location
  sku: {
    name: 'B1'                              // Basic B1 tier
    tier: 'Basic'
  }
}


// ==========================
// APPLICATION INSIGHTS
// ==========================

// Create Application Insights for monitoring the web app
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: '${resourcePrefix}-appinsights'
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'                 // Monitor a web app
  }
}


// ==========================
// WEB APP
// ==========================

// Create the Web App linked to App Insights
resource webApp 'Microsoft.Web/sites@2023-01-01' = {
  name: '${resourcePrefix}-webapp'
  location: location
  properties: {
    serverFarmId: appServicePlan.id         // Link to App Service Plan
    siteConfig: {
      appSettings: [                        // App Settings to integrate with App Insights
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: appInsights.properties.InstrumentationKey
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsights.properties.ConnectionString
        }
        {
          name: 'ApplicationInsightsAgent_EXTENSION_VERSION'
          value: '~2'
        }
      ]
    }
  }
}
