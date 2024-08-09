param location string = resourceGroup().location
param tags object
param deploymentNameStructure string
param environment string
param namingConvention string
param sequence int
param workloadName string
param imageReference object
param namingStructure string

param enableAvmTelemetry bool = true
param sampleImageName string = 'sample'

var customRoleName = 'Azure Image Builder Service Image Creation'
var customRoleGuid = guid(resourceGroup().id, customRoleName)

// Create a custom role that's allowed to create images
resource aibRoleDefinition 'Microsoft.Authorization/roleDefinitions@2022-04-01' = {
  name: customRoleGuid
  properties: {
    roleName: '${customRoleName} (${customRoleGuid})'
    description: 'Image Builder access to create resources for the image build'
    assignableScopes: [resourceGroup().id]
    permissions: [
      {
        actions: [
          'Microsoft.Compute/galleries/read'
          'Microsoft.Compute/galleries/images/read'
          'Microsoft.Compute/galleries/images/versions/read'
          'Microsoft.Compute/galleries/images/versions/write'

          'Microsoft.Compute/images/write'
          'Microsoft.Compute/images/read'
          'Microsoft.Compute/images/delete'

          'Microsoft.Network/virtualNetworks/read'
          'Microsoft.Network/virtualNetworks/subnets/join/action'
        ]
      }
    ]
  }
}

// TODO: Create dedicated UAMI for image building
module aibUamiModule '../../../shared-modules/security/uami.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'uami-aib'), 64)
  params: {
    location: location
    tags: tags
    uamiName: replace(namingStructure, '{rtype}', 'uami-aib')
  }
}

// Assign the new custom role to the UAMI
module uamiImagingRoleAssignmentModule '../../../module-library/roleAssignments/roleAssignment-rg.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'uami-img-rbac'), 64)
  params: {
    principalId: aibUamiModule.outputs.principalId
    roleDefinitionId: aibRoleDefinition.id
    principalType: 'ServicePrincipal'
  }
}

var aibNetworkAddressPrefix = '192.168.1.0/24'

module aibNetworkModule '../../../shared-modules/networking/main.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'network-aib'), 64)
  params: {
    deploymentNameStructure: deploymentNameStructure
    location: location
    namingStructure: namingStructure
    vnetAddressPrefixes: [aibNetworkAddressPrefix]

    subnetDefs: {
      ImageBuilderSubnet: {
        addressPrefix: cidrSubnet(aibNetworkAddressPrefix, 24, 0)
        privateLinkServiceNetworkPolicies: 'Disabled'
        // For compliance, all subnets need a NSG
        securityRules: []
      }
    }

    tags: tags
  }
}

module computeGalleryNameModule '../../../module-library/createValidAzResourceName.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'galname'), 64)
  params: {
    environment: environment
    location: location
    namingConvention: namingConvention
    resourceType: 'gal'
    sequence: sequence
    workloadName: workloadName
    subWorkloadName: ''
  }
  dependsOn: [uamiImagingRoleAssignmentModule]
}

module computeGalleryModule 'br/public:avm/res/compute/gallery:0.3.1' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'gal'), 64)
  params: {
    name: computeGalleryNameModule.outputs.validName
    location: location

    images: [
      {
        hyperVGeneration: 'V2'
        name: sampleImageName
        offer: 'WindowsClient'
        osType: 'Windows'
        publisher: 'Customer'
        sku: 'Windows-11-Enterprise-23H2-Gen2'

        securityType: 'TrustedLaunch'
        isAcceleratedNetworkSupported: true
        isHibernateSupported: true
        osState: 'Generalized'

        // Avoid warnings when using the image from the GUI
        maxRecommendedMemory: 4000
        maxRecommendedvCPUs: 128
        minRecommendedMemory: 4
        minRecommendedvCPUs: 2

        tags: tags
      }
    ]

    tags: tags
    enableTelemetry: enableAvmTelemetry
  }
}

module imageTemplateModule 'br/public:avm/res/virtual-machine-images/image-template:0.1.1' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'img'), 64)
  params: {
    name: replace(namingStructure, '{rtype}', 'img')
    location: location
    imageSource: union(imageReference, { type: 'PlatformImage' })

    // TODO: Load from customizable file
    customizationSteps: [
      {
        type: 'WindowsUpdate'
        filters: [
          'exclude:$_.Title -like \'*Preview*\''
          'include:$true'
        ]
      }
      {
        type: 'PowerShell'
        name: 'Install Microsoft Storage Explorer'
        runElevated: true
        runAsSystem: true
        // TODO: Use main branch
        scriptUri: 'https://raw.githubusercontent.com/SvenAelterman/Azure-HubAndSpokeResearchEnclave/main/scripts/PowerShell/Scripts/AIB/Windows/Install-StorageExplorer.ps1'
        sha256Checksum: 'a8122168d9700c8e3b2fe03804e181a88fdc4833bbeee19bd42e58e3d85903c5'
      }
      {
        type: 'PowerShell'
        name: 'Install azcopy'
        runElevated: true
        runAsSystem: true
        // TODO: Use main branch
        scriptUri: 'https://raw.githubusercontent.com/SvenAelterman/Azure-HubAndSpokeResearchEnclave/main/scripts/PowerShell/Scripts/AIB/Windows/Install-AzCopy.ps1'
        sha256Checksum: '45453a42a0d8d75f4aecb0e83566078373b3320489431b158f8ea4ae08379e59'
      }
    ]

    distributions: [
      {
        type: 'SharedImage'
        sharedImageGalleryImageDefinitionResourceId: '${computeGalleryModule.outputs.resourceId}/images/${sampleImageName}'
        excludeFromLatest: false
      }
    ]

    managedIdentities: {
      userAssignedResourceIds: [
        aibUamiModule.outputs.id
      ]
    }

    subnetResourceId: aibNetworkModule.outputs.createdSubnets.ImageBuilderSubnet.id

    enableTelemetry: enableAvmTelemetry
    tags: tags
  }
}
