import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../../../models/stock_credentials.dart';
import '../../../models/upload_job.dart';
import 'stock_upload_gateway.dart';

class SftpUploadGateway implements StockUploadGateway {
  const SftpUploadGateway();

  @override
  Stream<UploadProgressEvent> upload({
    required UploadJob job,
    required StockCredentials credentials,
  }) async* {
    final host = StockCredentials.sanitizeHost(credentials.hostname);
    if (host.isEmpty) {
      throw Exception('Host is empty for ${job.stockKey}.');
    }
    if (credentials.username.trim().isEmpty) {
      throw Exception('Username is empty for ${job.stockKey}.');
    }

    final file = File(job.filePath);
    if (!await file.exists()) {
      throw Exception('File not found: ${job.filePath}');
    }

    final fileSize = await file.length();
    yield const UploadProgressEvent(0.01, message: 'Connecting to SFTP...');

    SSHClient? client;
    try {
      // 1. Connect
      final socket = await SSHSocket.connect(
        host,
        22,
        timeout: const Duration(seconds: 10),
      );

      client = SSHClient(
        socket,
        username: credentials.username.trim(),
        onPasswordRequest: () => credentials.password.trim(),
      );

      yield const UploadProgressEvent(0.05, message: 'Authenticating...');
      await client.authenticated;
      yield const UploadProgressEvent(
        0.1,
        message: 'Authenticated. Opening SFTP...',
      );

      // 2. Open SFTP Session
      final sftp = await client.sftp();
      yield const UploadProgressEvent(
        0.15,
        message: 'SFTP session established.',
      );

      // 3. Open remote file for writing
      final remoteFilename = job.filename;
      final remoteFile = await sftp.open(
        remoteFilename,
        mode: SftpFileOpenMode.create | SftpFileOpenMode.write,
      );

      yield const UploadProgressEvent(0.2, message: 'Uploading...');

      // 4. Stream local file to remote file
      int bytesUploaded = 0;
      final stream = file.openRead();

      // Write chunks
      const maxChunkSize = 16 * 1024; // 16KB max per SFTP request
      await for (final chunk in stream) {
        final data = chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
        
        // AWS Transfer / S3 requires strictly sequential writes.
        // dartssh2 might parallelize if it exceeds its internal maxChunkSize,
        // so we manually slice to maxChunkSize and write sequentially with an explicit offset in case it's needed by the underlying provider.
        int chunkOffset = 0;
        while (chunkOffset < data.length) {
          final size = data.length - chunkOffset > maxChunkSize
              ? maxChunkSize
              : data.length - chunkOffset;
          
          final slice = Uint8List.sublistView(
            data,
            chunkOffset,
            chunkOffset + size,
          );

          // We await each smaller packet sequentially and pass absolute offset
          await remoteFile.writeBytes(slice, offset: bytesUploaded);

          chunkOffset += size;
          bytesUploaded += size;
        }

        // Progress between 0.2 and 0.99
        final progress = 0.2 + (0.79 * (bytesUploaded / fileSize));
        yield UploadProgressEvent(progress);
      }

      await remoteFile.close();
      yield const UploadProgressEvent(1.0, message: 'Upload complete.');
    } finally {
      client?.close();
    }
  }
}
