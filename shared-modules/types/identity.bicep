@description('The managed identity type assigned to an Azure resource.')
@export()
type identity = 'None' | 'SystemAssigned' | 'UserAssigned' | 'SystemAssigned, UserAssigned'
