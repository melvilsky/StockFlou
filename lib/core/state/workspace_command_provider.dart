import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Действия, которые инициируются из глобальной панели, а выполняются
/// workspace-экраном с его собственными диалогами и контекстом.
enum WorkspaceCommand { importFiles, importCsv, openFolder, refresh }

/// Событие с монотонным id: повторная отправка того же действия
/// должна срабатывать снова.
class WorkspaceCommandEvent {
  final WorkspaceCommand command;
  final int sequence;

  const WorkspaceCommandEvent(this.command, this.sequence);
}

class WorkspaceCommandNotifier extends Notifier<WorkspaceCommandEvent?> {
  int _sequence = 0;

  @override
  WorkspaceCommandEvent? build() => null;

  void emit(WorkspaceCommand command) {
    _sequence++;
    state = WorkspaceCommandEvent(command, _sequence);
  }
}

final workspaceCommandProvider =
    NotifierProvider<WorkspaceCommandNotifier, WorkspaceCommandEvent?>(
      WorkspaceCommandNotifier.new,
    );
