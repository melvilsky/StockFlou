import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../models/app_file.dart';
import '../../models/stock_credentials.dart';
import '../../models/upload_job.dart';
import '../../models/workflow_status.dart';
import '../database/database_helper.dart';
import '../services/upload/stock_upload_gateway.dart';
import 'files_provider.dart';
import 'settings_provider.dart';

final stockUploadGatewayProvider = Provider<StockUploadGateway>(
  (ref) => const SocketHandshakeUploadGateway(),
);

class UploadQueueNotifier extends AsyncNotifier<List<UploadJob>> {
  bool _processing = false;

  @override
  Future<List<UploadJob>> build() async {
    return DatabaseHelper.instance.getUploadJobs();
  }

  Future<void> enqueueFiles({
    required List<AppFile> files,
    required String stockKey,
    required UploadProtocol protocol,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final jobs = <UploadJob>[];

    for (final file in files) {
      if (!file.workflowStatus.canBeQueuedForUpload) {
        continue;
      }
      jobs.add(
        UploadJob(
          id: const Uuid().v4(),
          fileId: file.id,
          filePath: file.path,
          filename: file.filename,
          stockKey: stockKey,
          protocol: protocol,
          createdAt: now,
          updatedAt: now,
        ),
      );
      final ready = file.copyWith(workflowStatus: WorkflowStatus.readyToUpload);
      await ref.read(filesProvider.notifier).updateFile(ready);
    }

    if (jobs.isEmpty) return;

    final current = state.value ?? [];
    state = AsyncData([...jobs, ...current]);
    for (final job in jobs) {
      await DatabaseHelper.instance.insertUploadJob(job);
    }
    unawaited(processQueue());
  }

  Future<void> processQueue() async {
    if (_processing) return;
    _processing = true;
    try {
      while (true) {
        final snapshot = state.value ?? [];
        final next = snapshot.firstWhere(
          (job) => job.status == UploadJobStatus.pending,
          orElse: () => const UploadJob(
            id: '',
            fileId: '',
            filePath: '',
            filename: '',
            stockKey: '',
            protocol: UploadProtocol.sftp,
            createdAt: 0,
            updatedAt: 0,
          ),
        );

        if (next.id.isEmpty) break;
        await _runJob(next);
      }
    } finally {
      _processing = false;
    }
  }

  Future<void> pauseJob(String jobId) async {
    await _patchJob(
      jobId,
      (job) => job.copyWith(
        status: UploadJobStatus.paused,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  Future<void> resumeJob(String jobId) async {
    await _patchJob(
      jobId,
      (job) => job.copyWith(
        status: UploadJobStatus.pending,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    unawaited(processQueue());
  }

  Future<void> cancelJob(String jobId) async {
    await _patchJob(
      jobId,
      (job) => job.copyWith(
        status: UploadJobStatus.cancelled,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  Future<void> retryJob(String jobId) async {
    await _patchJob(
      jobId,
      (job) => job.copyWith(
        status: UploadJobStatus.pending,
        progress: 0,
        errorMessage: null,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    unawaited(processQueue());
  }

  Future<void> cancelAll() async {
    final jobs = state.value ?? [];
    for (final job in jobs.where(
      (j) =>
          j.status == UploadJobStatus.pending ||
          j.status == UploadJobStatus.uploading ||
          j.status == UploadJobStatus.paused,
    )) {
      await cancelJob(job.id);
    }
  }

  Future<void> _runJob(UploadJob job) async {
    final uploading = job.copyWith(
      status: UploadJobStatus.uploading,
      progress: 0.05,
      errorMessage: null,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _replace(uploading);

    final credentials = _resolveCredentials(uploading.stockKey);
    if (credentials == null || credentials.isEmpty) {
      await _failJob(uploading, 'Missing credentials for ${uploading.stockKey}.');
      return;
    }

    try {
      final gateway = ref.read(stockUploadGatewayProvider);
      await for (final event in gateway.upload(
        job: uploading,
        credentials: credentials,
      )) {
        final current = _findById(uploading.id);
        if (current == null || current.status != UploadJobStatus.uploading) {
          return;
        }
        await _replace(
          current.copyWith(
            progress: event.progress,
            updatedAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
      }

      final completed = _findById(uploading.id);
      if (completed == null || completed.status != UploadJobStatus.uploading) {
        return;
      }
      final success = completed.copyWith(
        status: UploadJobStatus.success,
        progress: 1,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      await _replace(success);
      await _markFileUploaded(success.fileId);
    } catch (e) {
      await _failJob(uploading, e.toString());
    }
  }

  Future<void> _markFileUploaded(String fileId) async {
    final files = ref.read(filesProvider).value ?? [];
    final file = files.where((f) => f.id == fileId).firstOrNull;
    if (file == null) return;
    await ref
        .read(filesProvider.notifier)
        .updateFile(file.copyWith(workflowStatus: WorkflowStatus.uploaded));
  }

  Future<void> _failJob(UploadJob base, String message) async {
    final latest = _findById(base.id) ?? base;
    await _replace(
      latest.copyWith(
        status: UploadJobStatus.error,
        errorMessage: message,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  StockCredentials? _resolveCredentials(String stockKey) {
    final settings = ref.read(settingsProvider).value;
    if (settings == null) return null;
    switch (stockKey) {
      case 'adobe':
        return settings.adobeCredentials;
      case 'shutterstock':
        return settings.shutterstockCredentials;
      default:
        return null;
    }
  }

  Future<void> _patchJob(
    String jobId,
    UploadJob Function(UploadJob) patch,
  ) async {
    final target = _findById(jobId);
    if (target == null) return;
    await _replace(patch(target));
  }

  UploadJob? _findById(String id) {
    final jobs = state.value ?? [];
    for (final job in jobs) {
      if (job.id == id) return job;
    }
    return null;
  }

  Future<void> _replace(UploadJob updated) async {
    final jobs = state.value ?? [];
    state = AsyncData([
      for (final item in jobs)
        if (item.id == updated.id) updated else item,
    ]);
    await DatabaseHelper.instance.updateUploadJob(updated);
  }
}

final uploadQueueProvider =
    AsyncNotifierProvider<UploadQueueNotifier, List<UploadJob>>(
      UploadQueueNotifier.new,
    );

extension _IterableFirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
