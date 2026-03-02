import 'dart:async';
import 'dart:io';

import '../../../models/stock_credentials.dart';
import '../../../models/upload_job.dart';

class UploadProgressEvent {
  final double progress;
  final String? message;

  const UploadProgressEvent(this.progress, {this.message});
}

abstract class StockUploadGateway {
  Stream<UploadProgressEvent> upload({
    required UploadJob job,
    required StockCredentials credentials,
  });
}

/// Phase-1 gateway: checks FTPS/SFTP host connectivity and then simulates
/// chunked progress. This keeps queue lifecycle real and testable while
/// protocol-specific file transfer implementation is added in next increment.
class SocketHandshakeUploadGateway implements StockUploadGateway {
  const SocketHandshakeUploadGateway();

  @override
  Stream<UploadProgressEvent> upload({
    required UploadJob job,
    required StockCredentials credentials,
  }) async* {
    if (credentials.hostname.trim().isEmpty) {
      throw Exception('Host is empty for ${job.stockKey}.');
    }

    final port = job.protocol == UploadProtocol.sftp ? 22 : 21;
    Socket? socket;
    try {
      socket = await Socket.connect(
        credentials.hostname.trim(),
        port,
        timeout: const Duration(seconds: 4),
      );
      yield const UploadProgressEvent(0.2, message: 'Connected');
    } finally {
      await socket?.close();
    }

    for (final value in [0.4, 0.6, 0.8, 1.0]) {
      await Future.delayed(const Duration(milliseconds: 350));
      yield UploadProgressEvent(value);
    }
  }
}
