param location string
param namingStructure string
param subWorkloadName string
param resourceId string
param topicName string
param tags object = {}

var baseName = !empty(subWorkloadName) ? replace(namingStructure, '{subWorkloadName}', subWorkloadName) : replace(namingStructure, '-{subWorkloadName}', '')

resource eventGridSystemTopic 'Microsoft.EventGrid/systemTopics@2021-06-01-preview' = {
  name: replace(baseName, '{rtype}', 'evgt')
  location: location
  properties: {
    source: resourceId
    topicType: topicName
  }
  tags: tags
}

output systemTopicName string = eventGridSystemTopic.name
