@description('Active Directory domain information and credentials used to join a resource to the domain.')
@export()
type activeDirectoryDomainInfo = {
  @description('The password of the account used to join the domain.')
  @secure()
  domainJoinPassword: string
  @description('The username of the account used to join the domain.')
  @secure()
  domainJoinUsername: string

  @description('The fully qualified domain name of the Active Directory domain.')
  adDomainFqdn: string
  @description('The distinguished name of the organizational unit in which to place the domain-joined resource.')
  adOuPath: string?
}
