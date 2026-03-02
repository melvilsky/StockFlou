import '../../models/app_file.dart';
import '../../models/qc_report.dart';

class QcChecker {
  static const int minKeywords = 5;
  static const int maxKeywordsWarning = 50;

  QcReport validateFile(AppFile file, String stockKey) {
    final issues = <QcIssue>[];

    // Check title
    if (file.metadataTitle == null || file.metadataTitle!.trim().isEmpty) {
      issues.add(
        const QcIssue(
          isError: true,
          message: 'Title is missing or empty',
          field: 'Title',
        ),
      );
    }

    // Check description
    if (file.metadataDescription == null ||
        file.metadataDescription!.trim().isEmpty) {
      issues.add(
        const QcIssue(
          isError: true,
          message: 'Description is missing or empty',
          field: 'Description',
        ),
      );
    }

    // Check keywords (comma-separated string)
    final keywordString = file.metadataKeywords ?? '';
    final keywords = keywordString
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (keywords.length < minKeywords) {
      issues.add(
        QcIssue(
          isError: true,
          message:
              'At least $minKeywords keywords are required (found ${keywords.length})',
          field: 'Keywords',
        ),
      );
    } else if (keywords.length > maxKeywordsWarning) {
      issues.add(
        QcIssue(
          isError: false,
          message:
              'More than $maxKeywordsWarning keywords might be rejected by some agencies (found ${keywords.length})',
          field: 'Keywords',
        ),
      );
    }

    // Check duplicates
    final uniqueKeywords = keywords.map((k) => k.toLowerCase().trim()).toSet();
    if (uniqueKeywords.length < keywords.length) {
      issues.add(
        const QcIssue(
          isError: false,
          message: 'Contains duplicate keywords',
          field: 'Keywords',
        ),
      );
    }

    return QcReport(fileId: file.id, issues: issues);
  }
}
