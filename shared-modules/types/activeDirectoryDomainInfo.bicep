@export()
type activeDirectoryDomainInfo = {
  @secure()
  domainJoinPassword: string
  @secure()
  domainJoinUsername: string
  adDomainFqdn: string
  adOuPath: string?
}
