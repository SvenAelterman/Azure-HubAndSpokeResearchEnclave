param redisCacheName string
param principalId string
param roleDefinitionId string

resource redis 'Microsoft.Cache/redis@2022-06-01' existing = {
  name: redisCacheName
}

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2020-10-01-preview' = {
  name: guid(redis.id, principalId, roleDefinitionId)
  scope: redis
  properties: {
    roleDefinitionId: roleDefinitionId
    principalId: principalId
  }
}
