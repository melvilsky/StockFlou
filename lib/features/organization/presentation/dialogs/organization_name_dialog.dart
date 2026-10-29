import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Диалог ввода/редактирования имени проекта или коллекции с валидацией.
///
/// Гарантирует:
/// - непустое имя (с предварительным `trim()`);
/// - запрет имени, состоящего только из пробелов;
/// - ограничение длины (максимум 100 символов);
/// - клавиатурную навигацию (Enter — подтвердить, Esc — отменить, автофокус).
class OrganizationNameDialog extends StatefulWidget {
  final String title;
  final String initialValue;
  final String label;
  final String confirmButtonText;

  const OrganizationNameDialog({
    super.key,
    required this.title,
    this.initialValue = '',
    this.label = 'Название',
    this.confirmButtonText = 'Сохранить',
  });

  static Future<String?> show({
    required BuildContext context,
    required String title,
    String initialValue = '',
    String label = 'Название',
    String confirmButtonText = 'Сохранить',
  }) {
    return showDialog<String>(
      context: context,
      builder: (context) => OrganizationNameDialog(
        title: title,
        initialValue: initialValue,
        label: label,
        confirmButtonText: confirmButtonText,
      ),
    );
  }

  @override
  State<OrganizationNameDialog> createState() => _OrganizationNameDialogState();
}

class _OrganizationNameDialogState extends State<OrganizationNameDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _focusNode = FocusNode();
    if (widget.initialValue.isNotEmpty) {
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: widget.initialValue.length,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState?.validate() ?? false) {
      Navigator.of(context).pop(_controller.text.trim());
    }
  }

  String? _validateName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Название не может быть пустым';
    }
    if (value.trim().length > 100) {
      return 'Название не должно превышать 100 символов';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AlertDialog(
      title: Text(widget.title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 320, maxWidth: 440),
        child: Form(
          key: _formKey,
          child: TextFormField(
            key: const Key('organization_name_input'),
            controller: _controller,
            focusNode: _focusNode,
            autofocus: true,
            maxLength: 100,
            maxLengthEnforcement: MaxLengthEnforcement.none,
            decoration: InputDecoration(
              labelText: widget.label,
              hintText: 'Введите название',
              border: const OutlineInputBorder(),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: colorScheme.primary, width: 2),
              ),
            ),
            validator: _validateName,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _submit(),
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('organization_name_cancel_button'),
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Отмена'),
        ),
        FilledButton(
          key: const Key('organization_name_submit_button'),
          onPressed: _submit,
          child: Text(widget.confirmButtonText),
        ),
      ],
    );
  }
}
