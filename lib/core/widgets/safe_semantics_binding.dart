import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

class StockFlowBinding extends WidgetsFlutterBinding
    with SafeSemanticsUpdates {}

/// Repairs incremental overlay updates before they reach the native AX tree.
mixin SafeSemanticsUpdates on RendererBinding, SemanticsBinding {
  final _nodes = <int, Map<Symbol, dynamic>>{};

  ui.SemanticsUpdateBuilder createPlatformSemanticsUpdateBuilder() =>
      super.createSemanticsUpdateBuilder();

  @override
  ui.SemanticsUpdateBuilder createSemanticsUpdateBuilder() =>
      _SafeUpdate(this, createPlatformSemanticsUpdateBuilder());

  void _pruneDetachedNodes() {
    final live = <int>{};
    void visit(SemanticsNode node) {
      if (!live.add(node.id)) return;
      node.visitChildren((child) {
        visit(child);
        return true;
      });
    }

    void visitOwner(PipelineOwner owner) {
      final root = owner.semanticsOwner?.rootSemanticsNode;
      if (root != null) visit(root);
      owner.visitChildren(visitOwner);
    }

    visitOwner(rootPipelineOwner);
    _nodes.removeWhere((id, _) => !live.contains(id));
  }
}

class _SafeUpdate implements ui.SemanticsUpdateBuilder {
  final SafeSemanticsUpdates binding;
  final ui.SemanticsUpdateBuilder delegate;

  _SafeUpdate(this.binding, this.delegate);

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #updateNode) {
      binding._nodes[invocation.namedArguments[#id] as int] = Map.of(
        invocation.namedArguments,
      );
      return null;
    }
    if (invocation.memberName == #updateCustomAction) {
      return Function.apply(
        delegate.updateCustomAction,
        invocation.positionalArguments,
        invocation.namedArguments,
      );
    }
    if (invocation.memberName == #build) {
      binding._pruneDetachedNodes();
      final reachable = <int>{};
      final visiting = <int>{};
      bool visit(int id) {
        if (visiting.contains(id) || reachable.contains(id)) return false;
        final node = binding._nodes[id];
        if (node == null) return false;
        visiting.add(id);
        for (final child in node[#childrenInTraversalOrder] ?? <int>[]) {
          if (!visit(child as int)) return false;
        }
        visiting.remove(id);
        reachable.add(id);
        return true;
      }

      // shortcut: Flutter #193372/#193588 can send orphaned or moved nodes
      // without their data. Replay a complete rooted snapshot until fixed upstream.
      if (visit(0)) {
        for (final id in reachable) {
          Function.apply(delegate.updateNode, const [], binding._nodes[id]);
        }
      }
      return delegate.build();
    }
    return super.noSuchMethod(invocation);
  }
}
