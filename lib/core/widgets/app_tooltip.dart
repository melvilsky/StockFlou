import 'package:flutter/material.dart';

/// Keeps sibling tooltip overlay anchors in separate accessibility nodes.
class AppTooltip extends StatelessWidget {
  final String message;
  final Widget child;

  const AppTooltip({super.key, required this.message, required this.child});

  @override
  Widget build(BuildContext context) {
    // shortcut: Flutter #182444 merges sibling overlay anchors; remove after its fix.
    return Semantics(
      container: true,
      child: Tooltip(message: message, child: child),
    );
  }
}
