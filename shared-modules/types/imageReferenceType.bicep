@description('The reference to a platform, marketplace, or custom virtual machine image.')
@export()
type imageReferenceType = {
  @description('The publisher of the marketplace image.')
  publisher: string?
  @description('The offer of the marketplace image.')
  offer: string?
  @description('The version of the marketplace image.')
  version: string?
  @description('The SKU of the marketplace image.')
  sku: string?
  @description('The resource ID of a custom image.')
  id: string?
}
