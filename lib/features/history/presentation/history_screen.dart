import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Row(
          children: [
            Text(
              'Workspace',
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 16,
              color: colorScheme.onSurface.withValues(alpha: 0.5),
            ),
            const SizedBox(width: 4),
            const Text(
              'Upload Queue',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        backgroundColor: colorScheme.surface,
        scrolledUnderElevation: 0,
        actions: [
          Container(
            height: 36,
            margin: const EdgeInsets.symmetric(vertical: 10),
            child: OutlinedButton.icon(
              onPressed: () {},
              icon: Icon(Icons.pause, size: 16, color: colorScheme.onSurface),
              label: Text(
                'Pause',
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: colorScheme.outline),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Builder(
            builder: (context) {
              final isDark = Theme.of(context).brightness == Brightness.dark;
              final destructiveColor = isDark
                  ? AppTheme.errorColorDark
                  : AppTheme.errorColor;
              return Container(
                height: 36,
                margin: const EdgeInsets.symmetric(vertical: 10),
                child: TextButton.icon(
                  onPressed: () {},
                  icon: Icon(
                    Icons.cancel_outlined,
                    size: 16,
                    color: destructiveColor,
                  ),
                  label: Text(
                    'Cancel All',
                    style: TextStyle(
                      color: destructiveColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    backgroundColor: destructiveColor.withValues(alpha: 0.1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 24),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: colorScheme.outline, height: 1),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Stat Cards Row
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    context,
                    icon: Icons.upload,
                    iconColor: Colors.blue.shade600,
                    iconBg: Colors.blue.withValues(alpha: 0.1),
                    title: 'Uploading',
                    count: '3',
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildStatCard(
                    context,
                    icon: Icons.hourglass_empty,
                    iconColor: Colors.orange.shade600,
                    iconBg: Colors.orange.withValues(alpha: 0.1),
                    title: 'Pending',
                    count: '12',
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildStatCard(
                    context,
                    icon: Icons.check_circle_outline,
                    iconColor: Colors.green.shade600,
                    iconBg: Colors.green.withValues(alpha: 0.1),
                    title: 'Completed',
                    count: '48',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            // Table Container
            Container(
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colorScheme.outline),
              ),
              child: Column(
                children: [
                  // Table Header
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Active Uploads',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.outlineVariant,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            'Total Progress: 45%',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurface.withValues(
                                alpha: 0.65,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: colorScheme.outline),
                  // Columns Outline
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 4,
                          child: Text('FILE', style: _colStyle(context)),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text('PLATFORM', style: _colStyle(context)),
                        ),
                        Expanded(
                          flex: 4,
                          child: Text('PROGRESS', style: _colStyle(context)),
                        ),
                        Expanded(
                          flex: 2,
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Text('STATUS', style: _colStyle(context)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: colorScheme.outline),
                  // Row 1
                  _buildRow(
                    context,
                    filename: 'City_Sunset_HDR.jpg',
                    sizeInfo: '12.4 MB • JPG',
                    platformAcronym: 'AS',
                    platformColor: Colors.red.shade400,
                    platformName: 'Adobe Stock',
                    progressText: 'Uploading...',
                    progressTextColor: Colors.blue.shade600,
                    progressValue: 0.45,
                    statusWidget: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.pause,
                          size: 20,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(width: 16),
                        Icon(
                          Icons.close,
                          size: 20,
                          color: Colors.grey.shade400,
                        ),
                      ],
                    ),
                  ),
                  // Row 2
                  _buildRow(
                    context,
                    filename: 'Portrait_Studio_05.jpg',
                    sizeInfo: '8.2 MB • JPG',
                    platformAcronym: 'SS',
                    platformColor: Colors.red.shade400,
                    platformName: 'Shutterstock',
                    progressText: 'Processing...',
                    progressTextColor: Colors.blue.shade600,
                    progressValue: 0.78,
                    statusWidget: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.pause,
                          size: 20,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(width: 16),
                        Icon(
                          Icons.close,
                          size: 20,
                          color: Colors.grey.shade400,
                        ),
                      ],
                    ),
                  ),
                  // Row 3 (Success)
                  _buildRow(
                    context,
                    filename: 'Office_Meeting_Room.jpg',
                    sizeInfo: '15.1 MB • JPG',
                    platformAcronym: 'G',
                    platformColor: Colors.blue.shade400,
                    platformName: 'Getty Images',
                    progressText: '',
                    progressTextColor: Colors.green.shade600,
                    progressValue: 1.0,
                    statusWidget: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Success',
                          style: TextStyle(
                            color: Colors.green,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.check_circle_outline,
                          color: Colors.green,
                          size: 18,
                        ),
                      ],
                    ),
                  ),
                  // Row 4 (Queue)
                  _buildRow(
                    context,
                    filename: 'Nature_Mountain_Lake.jpg',
                    sizeInfo: '18.5 MB • JPG',
                    platformAcronym: 'AS',
                    platformColor: Colors.red.shade400,
                    platformName: 'Adobe Stock',
                    progressText: 'Waiting in queue...',
                    progressTextColor: colorScheme.onSurface.withValues(
                      alpha: 0.5,
                    ),
                    progressValue: null,
                    statusWidget: Icon(
                      Icons.close,
                      size: 20,
                      color: Colors.grey.shade400,
                    ),
                  ),
                  // Row 5 (Error)
                  _buildRow(
                    context,
                    filename: 'Coffee_Morning_Vibe.jpg',
                    sizeInfo: '5.6 MB • JPG',
                    platformAcronym: 'AL',
                    platformColor: Colors.purple.shade400,
                    platformName: 'Alamy',
                    progressText: 'Error: Invalid Category ID',
                    progressTextColor: Colors.red.shade600,
                    progressValue: null,
                    hideBottomBorder: true,
                    statusWidget: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.refresh, color: Colors.blue, size: 16),
                        const SizedBox(width: 4),
                        const Text(
                          'Retry',
                          style: TextStyle(
                            color: Colors.blue,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Icon(
                          Icons.error_outline,
                          color: Colors.red,
                          size: 18,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String title,
    required String count,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outline),
        // subtle shadow
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                count,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  TextStyle _colStyle(BuildContext context) {
    return TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.bold,
      letterSpacing: 0.5,
      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
    );
  }

  Widget _buildRow(
    BuildContext context, {
    required String filename,
    required String sizeInfo,
    required String platformAcronym,
    required Color platformColor,
    required String platformName,
    required String progressText,
    required Color progressTextColor,
    required double? progressValue,
    required Widget statusWidget,
    bool hideBottomBorder = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        border: hideBottomBorder
            ? null
            : Border(bottom: BorderSide(color: colorScheme.outline)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          // FILE Column
          Expanded(
            flex: 4,
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: colorScheme.outlineVariant,
                    // image mock
                    image: const DecorationImage(
                      image: NetworkImage('https://picsum.photos/100'),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        filename,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        sizeInfo,
                        style: TextStyle(
                          color: colorScheme.onSurface.withValues(alpha: 0.5),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // PLATFORM Column
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: platformColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    platformAcronym,
                    style: TextStyle(
                      color: platformColor,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  platformName,
                  style: TextStyle(
                    color: colorScheme.onSurface.withValues(alpha: 0.8),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          // PROGRESS Column
          Expanded(
            flex: 4,
            child: Padding(
              padding: const EdgeInsets.only(right: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          if (progressValue == null &&
                              progressText.contains('Waiting'))
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: colorScheme.onSurface.withValues(
                                    alpha: 0.4,
                                  ),
                                ),
                              ),
                            ),
                          Text(
                            progressText,
                            style: TextStyle(
                              color: progressTextColor,
                              fontSize: 12,
                              fontWeight:
                                  progressValue != null ||
                                      progressText.contains('Error')
                                  ? FontWeight.w500
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                      if (progressValue != null)
                        Text(
                          '${(progressValue * 100).toInt()}%',
                          style: TextStyle(
                            color: colorScheme.onSurface.withValues(alpha: 0.5),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
                  if (progressValue != null) ...[
                    const SizedBox(height: 8),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        return Stack(
                          children: [
                            Container(
                              height: 6,
                              width: constraints.maxWidth,
                              decoration: BoxDecoration(
                                color: colorScheme.outlineVariant,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                            Container(
                              height: 6,
                              width: constraints.maxWidth * progressValue,
                              decoration: BoxDecoration(
                                color: progressTextColor,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
          // STATUS Column
          Expanded(
            flex: 2,
            child: Align(alignment: Alignment.centerRight, child: statusWidget),
          ),
        ],
      ),
    );
  }
}
