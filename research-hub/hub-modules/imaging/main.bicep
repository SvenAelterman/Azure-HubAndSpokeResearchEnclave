targetScope = 'subscription'

param resourceGroupName string
param location string
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

// Create a resource group
resource imagingRg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  #disable-next-line BCP334
  name: resourceGroupName
  location: location
  tags: tags
}

// Deploy the imaging resources
module imagingResourcesModule './aib-resources.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'aib'), 64)
  scope: imagingRg
  params: {
    location: location
    tags: tags
    deploymentNameStructure: deploymentNameStructure
    environment: environment
    namingConvention: namingConvention
    sequence: sequence
    workloadName: workloadName
    imageReference: imageReference
    namingStructure: namingStructure

    enableAvmTelemetry: enableAvmTelemetry
    sampleImageName: sampleImageName
  }
}

output imageDefinitionId string = imagingResourcesModule.outputs.imageDefinitionId
