/*
 * This type is designed to be compatible with that of Azure Verified Modules for future adoption.
 */

@export()
type roleAssignmentType = {
  // @description('Optional. The name (as GUID) of the role assignment. If not provided, a GUID will be generated.')
  // name: string?

  @description('Required. The role to assign. You can provide either the display name of the role definition, the role definition GUID, or its fully qualified ID in the following format: \'/providers/Microsoft.Authorization/roleDefinitions/c2f4ef07-c644-48eb-af81-4b1b4947fb11\'.')
  roleDefinitionId: string

  @description('Required. The principal ID of the principal (user/group/identity) to assign the role to.')
  principalId: string

  @description('Optional. The principal type of the assigned principal ID.')
  principalType: ('ServicePrincipal' | 'Group' | 'User' | 'ForeignGroup' | 'Device')?

  @description('Optional. The description of the role assignment.')
  description: string?

  // @description('Optional. The conditions on the role assignment. This limits the resources it can be assigned to. e.g.: @Resource[Microsoft.Storage/storageAccounts/blobServices/containers:ContainerName] StringEqualsIgnoreCase "foo_storage_container".')
  // condition: string?

  // @description('Optional. Version of the condition.')
  // conditionVersion: '2.0'?

  // @description('Optional. The Resource Id of the delegated managed identity resource.')
  // delegatedManagedIdentityResourceId: string?
}[]?
