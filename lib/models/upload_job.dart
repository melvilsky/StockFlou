enum UploadProtocol { sftp, ftps }

enum UploadJobStatus {
  pending,
  uploading,
  paused,
  success,
  error,
  cancelled,
}

extension UploadJobStatusX on UploadJobStatus {
  String get storageValue {
    switch (this) {
      case UploadJobStatus.pending:
        return 'pending';
      case UploadJobStatus.uploading:
        return 'uploading';
      case UploadJobStatus.paused:
        return 'paused';
      case UploadJobStatus.success:
        return 'success';
      case UploadJobStatus.error:
        return 'error';
      case UploadJobStatus.cancelled:
        return 'cancelled';
    }
  }
}

UploadJobStatus uploadJobStatusFromStorage(String value) {
  switch (value) {
    case 'uploading':
      return UploadJobStatus.uploading;
    case 'paused':
      return UploadJobStatus.paused;
    case 'success':
      return UploadJobStatus.success;
    case 'error':
      return UploadJobStatus.error;
    case 'cancelled':
      return UploadJobStatus.cancelled;
    case 'pending':
    default:
      return UploadJobStatus.pending;
  }
}

extension UploadProtocolX on UploadProtocol {
  String get storageValue => this == UploadProtocol.sftp ? 'sftp' : 'ftps';

  String get label => this == UploadProtocol.sftp ? 'SFTP' : 'FTPS';
}

UploadProtocol uploadProtocolFromStorage(String value) {
  return value == 'ftps' ? UploadProtocol.ftps : UploadProtocol.sftp;
}

class UploadJob {
  final String id;
  final String fileId;
  final String filePath;
  final String filename;
  final String stockKey;
  final UploadProtocol protocol;
  final UploadJobStatus status;
  final double progress;
  final String? errorMessage;
  final int createdAt;
  final int updatedAt;

  const UploadJob({
    required this.id,
    required this.fileId,
    required this.filePath,
    required this.filename,
    required this.stockKey,
    required this.protocol,
    this.status = UploadJobStatus.pending,
    this.progress = 0,
    this.errorMessage,
    required this.createdAt,
    required this.updatedAt,
  });

  UploadJob copyWith({
    UploadJobStatus? status,
    double? progress,
    Object? errorMessage = _sentinel,
    int? updatedAt,
  }) {
    return UploadJob(
      id: id,
      fileId: fileId,
      filePath: filePath,
      filename: filename,
      stockKey: stockKey,
      protocol: protocol,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      errorMessage: errorMessage == _sentinel
          ? this.errorMessage
          : errorMessage as String?,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'file_id': fileId,
      'file_path': filePath,
      'filename': filename,
      'stock_key': stockKey,
      'protocol': protocol.storageValue,
      'status': status.storageValue,
      'progress': progress,
      'error_message': errorMessage,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  factory UploadJob.fromMap(Map<String, dynamic> map) {
    return UploadJob(
      id: map['id'] as String,
      fileId: map['file_id'] as String,
      filePath: map['file_path'] as String,
      filename: map['filename'] as String,
      stockKey: map['stock_key'] as String,
      protocol: uploadProtocolFromStorage(map['protocol'] as String),
      status: uploadJobStatusFromStorage(map['status'] as String),
      progress: (map['progress'] as num?)?.toDouble() ?? 0,
      errorMessage: map['error_message'] as String?,
      createdAt: map['created_at'] as int,
      updatedAt: map['updated_at'] as int,
    );
  }
}

const _sentinel = Object();
