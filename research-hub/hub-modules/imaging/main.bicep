param location string = resourceGroup().location
param tags object
param deploymentNameStructure string
param environment string
param namingConvention string
param sequence int
param workloadName string
param uamiId string
param uamiPrincipalId string
param imageReference object
param namingStructure string

param enableAvmTelemetry bool = true
param sampleImageName string = 'sample'

var roleName = 'Azure Image Builder Service Image Creation'

// Create a custom role that's allowed to create images
resource aibRoleDefinition 'Microsoft.Authorization/roleDefinitions@2022-04-01' = {
  name: guid(resourceGroup().id, roleName)
  properties: {
    roleName: roleName
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
        ]
      }
    ]
  }
}

// Assign the new custom role to the UAMI
module uamiImagingRoleAssignmentModule '../../../module-library/roleAssignments/roleAssignment-rg.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'uami-img-rbac'), 64)
  params: {
    principalId: uamiPrincipalId
    roleDefinitionId: aibRoleDefinition.id
    principalType: 'ServicePrincipal'
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
    name: computeGalleryNameModule.outputs.shortName
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

        maxRecommendedMemory: 4000
        maxRecommendedvCPUs: 128
        minRecommendedMemory: 4
        minRecommendedvCPUs: 2
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

    // TODO: Load from customizable file
    customizationSteps: [
      {
        type: 'WindowsUpdate'
        filters: []
      }
      {
        type: 'PowerShell'
        name: 'Install Microsoft Storage Explorer'
        runElevated: true
        runAsSystem: true
        inline: [
          'winget install -e -h -s winget --id Microsoft.Azure.StorageExplorer --disable-interactivity --accept-package-agreements --accept-source-agreements --scope machine'
        ]
      }
    ]
    distributions: [
      {
        type: 'SharedImage'
        sharedImageGalleryImageDefinitionResourceId: '${computeGalleryModule.outputs.resourceId}/images/${sampleImageName}'
        excludeFromLatest: false
      }
    ]

    imageSource: union(imageReference, { type: 'PlatformImage' })
    managedIdentities: {
      userAssignedResourceIds: [
        uamiId
      ]
    }

    enableTelemetry: enableAvmTelemetry
    tags: tags
  }
}
