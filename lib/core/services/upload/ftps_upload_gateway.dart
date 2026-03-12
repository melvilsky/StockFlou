import 'dart:async';
import 'dart:io';

import 'package:ftpconnect/ftpconnect.dart';

import '../../../models/stock_credentials.dart';
import '../../../models/upload_job.dart';
import 'stock_upload_gateway.dart';

class FtpsUploadGateway implements StockUploadGateway {
  const FtpsUploadGateway();

  @override
  Stream<UploadProgressEvent> upload({
    required UploadJob job,
    required StockCredentials credentials,
  }) async* {
    if (credentials.hostname.trim().isEmpty) {
      throw Exception('Host is empty for ${job.stockKey}.');
    }
    if (credentials.username.trim().isEmpty) {
      throw Exception('Username is empty for ${job.stockKey}.');
    }

    final file = File(job.filePath);
    if (!await file.exists()) {
      throw Exception('File not found: ${job.filePath}');
    }

    yield const UploadProgressEvent(0.01, message: 'Connecting to FTPS...');

    FTPConnect? ftpConnect;
    try {
      // Create FTPConnect instance.
      // isSecured: true enables FTPS (FTP over TLS/SSL)
      ftpConnect = FTPConnect(
        credentials.hostname.trim(),
        user: credentials.username.trim(),
        pass: credentials.password.trim(),
        port: 21, // default FTPS port is usually 21 with explicit TLS
        securityType: SecurityType.ftpes, // FTP over Explicit TLS/SSL
        timeout: 30, // 30 seconds connection timeout
      );

      // Connect explicitly
      yield const UploadProgressEvent(
        0.05,
        message: 'Authenticating (FTPS)...',
      );
      final connected = await ftpConnect.connect();
      if (!connected) {
        throw Exception('Failed to connect to ${credentials.hostname}');
      }

      yield const UploadProgressEvent(
        0.1,
        message: 'Authenticated. Uploading...',
      );

      // Unfortunately, ftpconnect's uploadFile is synchronous-await and doesn't provide
      // chunked progress callbacks natively. We simulate progress during upload
      // or we can just yield complete when done since it might be fast enough.
      // To provide some feedback, we'll start a timer.

      bool uploadFinished = false;
      Object? uploadError;

      final uploadFuture = ftpConnect
          .uploadFile(file)
          .then((success) {
            uploadFinished = true;
            if (!success) {
              uploadError = Exception('FTP upload returned false');
            }
          })
          .catchError((e) {
            uploadFinished = true;
            uploadError = e;
          });

      double progress = 0.1;
      while (!uploadFinished) {
        await Future.delayed(const Duration(milliseconds: 500));
        if (uploadFinished) break;

        // Asymptotic progress up to 99%
        progress = progress + ((0.99 - progress) * 0.1);
        yield UploadProgressEvent(progress, message: 'Uploading...');
      }

      await uploadFuture; // wait to throw if error exists

      if (uploadError != null) {
        throw uploadError!;
      }

      yield const UploadProgressEvent(1.0, message: 'Upload complete.');
    } finally {
      await ftpConnect?.disconnect();
    }
  }
}
