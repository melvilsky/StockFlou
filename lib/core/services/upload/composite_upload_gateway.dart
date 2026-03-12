import 'dart:async';

import '../../../models/stock_credentials.dart';
import '../../../models/upload_job.dart';
import 'ftps_upload_gateway.dart';
import 'sftp_upload_gateway.dart';
import 'stock_upload_gateway.dart';

class CompositeUploadGateway implements StockUploadGateway {
  final SftpUploadGateway _sftpGateway;
  final FtpsUploadGateway _ftpsGateway;

  const CompositeUploadGateway({
    SftpUploadGateway sftpGateway = const SftpUploadGateway(),
    FtpsUploadGateway ftpsGateway = const FtpsUploadGateway(),
  }) : _sftpGateway = sftpGateway,
       _ftpsGateway = ftpsGateway;

  @override
  Stream<UploadProgressEvent> upload({
    required UploadJob job,
    required StockCredentials credentials,
  }) {
    if (job.protocol == UploadProtocol.sftp) {
      return _sftpGateway.upload(job: job, credentials: credentials);
    } else {
      return _ftpsGateway.upload(job: job, credentials: credentials);
    }
  }
}
