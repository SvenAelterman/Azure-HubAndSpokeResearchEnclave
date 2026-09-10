@description('The names of the data transfer pipelines used by the research enclave.')
@export()
type pipelineNamesType = {
  @description('The name of the pipeline that copies data from blob storage to a file share.')
  blobToFileShare: string
  @description('The name of the pipeline that copies data from a file share to blob storage.')
  fileShareToBlob: string
  @description('The name of the pipeline that copies data between file shares.')
  fileShareToFileShare: string
}
