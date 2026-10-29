import 'package:flutter/material.dart';

enum DuplicateAction {
  skip,
  queueAgain,
}

class DuplicateUploadResult {
  final DuplicateAction action;
  final bool applyToAll;

  const DuplicateUploadResult(this.action, this.applyToAll);
}

class DuplicateUploadDialog extends StatefulWidget {
  final String filename;
  final String stockName;

  const DuplicateUploadDialog({
    super.key,
    required this.filename,
    required this.stockName,
  });

  @override
  State<DuplicateUploadDialog> createState() => _DuplicateUploadDialogState();
}

class _DuplicateUploadDialogState extends State<DuplicateUploadDialog> {
  bool _applyToAll = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Файл уже загружен'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Файл "${widget.filename}" уже был успешно загружен на ${widget.stockName}. Хотите загрузить его повторно?',
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Checkbox(
                value: _applyToAll,
                onChanged: (val) {
                  setState(() {
                    _applyToAll = val ?? false;
                  });
                },
              ),
              const Expanded(
                child: Text('Применить ко всем дубликатам в этой партии'),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(
              context,
            ).pop(DuplicateUploadResult(DuplicateAction.skip, _applyToAll));
          },
          child: const Text('Пропустить'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop(
              DuplicateUploadResult(DuplicateAction.queueAgain, _applyToAll),
            );
          },
          child: const Text('В очередь'),
        ),
      ],
    );
  }
}
