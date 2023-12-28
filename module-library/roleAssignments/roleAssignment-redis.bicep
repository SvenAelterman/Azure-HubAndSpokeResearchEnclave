param redisCacheName string
param principalId string
param roleDefinitionId string

resource redis 'Microsoft.Cache/redis@2022-06-01' existing = {
  name: redisCacheName
}

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(redis.id, principalId, roleDefinitionId)
  scope: redis
  properties: {
    roleDefinitionId: roleDefinitionId
    principalId: principalId
  }
}
