import 'package:flutter/material.dart';

class KeywordsInputWidget extends StatefulWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  const KeywordsInputWidget({
    super.key,
    required this.controller,
    required this.onChanged,
  });

  @override
  State<KeywordsInputWidget> createState() => _KeywordsInputWidgetState();
}

class _KeywordsInputWidgetState extends State<KeywordsInputWidget> {
  late FocusNode _focusNode;
  final TextEditingController _inputController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    widget.controller.addListener(_updateFromParent);
  }

  void _updateFromParent() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_updateFromParent);
    _focusNode.dispose();
    _inputController.dispose();
    super.dispose();
  }

  List<String> get _keywords {
    return widget.controller.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  void _addKeyword(String val) {
    if (val.trim().isEmpty) return;
    final current = _keywords;
    // Don't add if it already exists to prevent duplicate exact strings
    if (!current.contains(val.trim())) {
      current.add(val.trim());
      widget.controller.text = current.join(', ');
      widget.onChanged(widget.controller.text);
    }
    _inputController.clear();
  }

  void _removeKeyword(String keyword) {
    final current = _keywords;
    current.remove(keyword);
    widget.controller.text = current.join(', ');
    widget.onChanged(widget.controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: () => _focusNode.requestFocus(),
      child: InputDecorator(
        isFocused: _focusNode.hasFocus,
        decoration: InputDecoration(
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: colorScheme.outline),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: colorScheme.outline.withValues(alpha: 0.5)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: colorScheme.primary, width: 2),
          ),
        ),
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ..._keywords.map((kw) => Chip(
                  label: Text(kw, style: TextStyle(fontSize: 12, color: colorScheme.onSurface)),
                  padding: EdgeInsets.zero,
                  visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
                  onDeleted: () => _removeKeyword(kw),
                  deleteIcon: const Icon(Icons.close, size: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  backgroundColor: colorScheme.surfaceContainerHighest,
                  side: BorderSide(color: colorScheme.outline.withValues(alpha: 0.2)),
                )),
            IntrinsicWidth(
              child: TextField(
                controller: _inputController,
                focusNode: _focusNode,
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: _keywords.isEmpty ? 'Введите ключи через запятую...' : 'Добавить...',
                  hintStyle: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
                style: const TextStyle(fontSize: 13),
                onSubmitted: _addKeyword,
                onChanged: (val) {
                  if (val.contains(',')) {
                    final parts = val.split(',');
                    for (int i = 0; i < parts.length - 1; i++) {
                      _addKeyword(parts[i]);
                    }
                    _inputController.text = parts.last;
                    _inputController.selection = TextSelection.fromPosition(
                        TextPosition(offset: _inputController.text.length));
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
