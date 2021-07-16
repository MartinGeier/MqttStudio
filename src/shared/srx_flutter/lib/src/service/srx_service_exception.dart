class SrxServiceException implements Exception {
  String errorMessage;
  dynamic serviceError;
  SrxServiceException(this.errorMessage, this.serviceError);
}
