import 'package:flutter/foundation.dart';

/// Состояние доступности рабочей папки.
enum WorkspaceAvailabilityStatus {
  /// Проверяется доступность.
  checking,

  /// Папка существует и доступна для чтения.
  available,

  /// Папка недоступна (диск отключён, нет прав или путь не найден).
  unavailable,
}

@immutable
class WorkspaceAvailability {
  final WorkspaceAvailabilityStatus status;
  final String? message;

  const WorkspaceAvailability({
    required this.status,
    this.message,
  });

  const WorkspaceAvailability.checking([this.message])
      : status = WorkspaceAvailabilityStatus.checking;

  const WorkspaceAvailability.available([this.message])
      : status = WorkspaceAvailabilityStatus.available;

  const WorkspaceAvailability.unavailable([this.message])
      : status = WorkspaceAvailabilityStatus.unavailable;

  bool get isChecking => status == WorkspaceAvailabilityStatus.checking;
  bool get isAvailable => status == WorkspaceAvailabilityStatus.available;
  bool get isUnavailable => status == WorkspaceAvailabilityStatus.unavailable;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WorkspaceAvailability &&
          runtimeType == other.runtimeType &&
          status == other.status &&
          message == other.message;

  @override
  int get hashCode => Object.hash(status, message);

  @override
  String toString() => 'WorkspaceAvailability($status, message: $message)';
}
