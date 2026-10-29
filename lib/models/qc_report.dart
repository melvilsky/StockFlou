class QcIssue {
  final bool isError;
  final String message;
  final String field;

  const QcIssue({
    required this.isError,
    required this.message,
    required this.field,
  });

  bool get isWarning => !isError;
}

class QcReport {
  final String fileId;
  final List<QcIssue> issues;

  const QcReport({required this.fileId, this.issues = const []});

  bool get hasErrors => issues.any((issue) => issue.isError);
  bool get hasWarnings => issues.any((issue) => issue.isWarning);
  bool get isClean => issues.isEmpty;

  List<QcIssue> get errors => issues.where((i) => i.isError).toList();
  List<QcIssue> get warnings => issues.where((i) => i.isWarning).toList();
}
