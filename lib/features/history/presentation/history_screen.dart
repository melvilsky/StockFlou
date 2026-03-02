import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/state/files_provider.dart';
import '../../../core/state/upload_queue_provider.dart';
import '../../../models/upload_job.dart';
import '../../../models/workflow_status.dart';
import '../../../models/qc_report.dart';
import '../../../core/services/qc_checker.dart';
import 'widgets/qc_report_dialog.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final queueState = ref.watch(uploadQueueProvider);
    final filesState = ref.watch(filesProvider);

    final jobs = queueState.value ?? const <UploadJob>[];
    final files = filesState.value ?? const [];
    final readyFiles = files
        .where((f) => f.workflowStatus.canBeQueuedForUpload)
        .toList();

    final uploadingCount = jobs
        .where((j) => j.status == UploadJobStatus.uploading)
        .length;
    final pendingCount = jobs
        .where((j) => j.status == UploadJobStatus.pending)
        .length;
    final completedCount = jobs
        .where((j) => j.status == UploadJobStatus.success)
        .length;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Upload Queue'),
        backgroundColor: colorScheme.surface,
        scrolledUnderElevation: 0,
        actions: [
          TextButton.icon(
            onPressed: readyFiles.isEmpty
                ? null
                : () async {
                    // 1. Run QC
                    final checker = QcChecker();
                    final reports = <String, QcReport>{};
                    bool hasIssues = false;
                    for (final file in readyFiles) {
                      final report = checker.validateFile(file, 'adobe');
                      if (!report.isClean) {
                        reports[file.id] = report;
                        hasIssues = true;
                      }
                    }

                    // 2. If issues found, show dialog
                    if (hasIssues) {
                      final shouldProceed = await showDialog<bool>(
                        context: context,
                        builder: (ctx) =>
                            QcReportDialog(files: readyFiles, reports: reports),
                      );
                      // If user cancelled or dialog was blocked by errors
                      if (shouldProceed != true) return;
                    }

                    // 3. Queue files
                    if (context.mounted) {
                      ref
                          .read(uploadQueueProvider.notifier)
                          .enqueueFiles(
                            files: readyFiles,
                            stockKey: 'adobe',
                            protocol: UploadProtocol.sftp,
                          );
                    }
                  },
            icon: const Icon(Icons.add),
            label: Text('Queue ready (${readyFiles.length})'),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: () =>
                ref.read(uploadQueueProvider.notifier).processQueue(),
            icon: const Icon(Icons.play_arrow, size: 16),
            label: const Text('Start'),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: () => ref.read(uploadQueueProvider.notifier).cancelAll(),
            icon: const Icon(Icons.cancel_outlined, size: 16),
            label: const Text('Cancel all'),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Row(
              children: [
                _StatCard(title: 'Uploading', count: uploadingCount.toString()),
                const SizedBox(width: 12),
                _StatCard(title: 'Pending', count: pendingCount.toString()),
                const SizedBox(width: 12),
                _StatCard(title: 'Completed', count: completedCount.toString()),
              ],
            ),
            const SizedBox(height: 18),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colorScheme.outline),
                ),
                child: jobs.isEmpty
                    ? const Center(
                        child: Text(
                          'Очередь пуста. Добавьте ready-to-upload файлы.',
                        ),
                      )
                    : ListView.separated(
                        itemCount: jobs.length,
                        separatorBuilder: (_, __) =>
                            Divider(height: 1, color: colorScheme.outline),
                        itemBuilder: (context, index) {
                          final job = jobs[index];
                          return _JobRow(job: job);
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String count;

  const _StatCard({required this.title, required this.count});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colorScheme.outline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              count,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}

class _JobRow extends ConsumerWidget {
  final UploadJob job;

  const _JobRow({required this.job});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      title: Text(job.filename, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${job.stockKey.toUpperCase()} • ${job.protocol.label} • ${job.status.storageValue}',
      ),
      trailing: SizedBox(
        width: 260,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: LinearProgressIndicator(
                value: job.progress <= 0 ? null : job.progress.clamp(0, 1),
              ),
            ),
            IconButton(
              tooltip: 'Pause',
              onPressed: job.status == UploadJobStatus.uploading
                  ? () =>
                        ref.read(uploadQueueProvider.notifier).pauseJob(job.id)
                  : null,
              icon: const Icon(Icons.pause, size: 18),
            ),
            IconButton(
              tooltip: 'Resume',
              onPressed: job.status == UploadJobStatus.paused
                  ? () =>
                        ref.read(uploadQueueProvider.notifier).resumeJob(job.id)
                  : null,
              icon: const Icon(Icons.play_arrow, size: 18),
            ),
            IconButton(
              tooltip: 'Retry',
              onPressed: job.status == UploadJobStatus.error
                  ? () =>
                        ref.read(uploadQueueProvider.notifier).retryJob(job.id)
                  : null,
              icon: const Icon(Icons.refresh, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}
