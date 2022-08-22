import 'dart:collection';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:super_editor/src/core/document_selection.dart';
import 'package:super_editor/src/infrastructure/_logging.dart';
import 'package:uuid/uuid.dart';

import 'document.dart';

/// Editor for a [Document].
///
/// A [DocumentEditor] executes commands that alter the structure
/// of a [Document]. Commands are used so that document changes
/// can be event-sourced, allowing for undo/redo behavior.
// TODO: design and implement comprehensive event-sourced editing API (#49)
class DocumentEditor {
  static const Uuid _uuid = Uuid();

  /// Generates a new ID for a [DocumentNode].
  ///
  /// Each generated node ID is universally unique.
  static String createNodeId() => _uuid.v4();

  /// Constructs a [DocumentEditor] that makes changes to the given
  /// [MutableDocument].
  DocumentEditor({
    required MutableDocument document,
  }) : _document = document;

  final MutableDocument _document;

  /// Returns a read-only version of the [Document] that this editor
  /// is editing.
  Document get document => _document;

  /// Executes the given [command] to alter the [Document] that is tied
  /// to this [DocumentEditor].
  void executeCommand(EditorCommand command) {
    command.execute(_document, DocumentEditorTransaction._(_document));
  }
}

/// A command that alters a [Document] by applying changes in a
/// [DocumentEditorTransaction].
abstract class EditorCommand {
  /// Executes this command against the given [document], with changes
  /// applied to the given [transaction].
  ///
  /// The [document] is provided in case this command needs to query
  /// the current content of the [document] to make appropriate changes.
  void execute(Document document, DocumentEditorTransaction transaction);
}

/// Functional version of an [EditorCommand] for commands that
/// don't require variables or private functions.
class EditorCommandFunction implements EditorCommand {
  /// Creates a functional editor command given the [EditorCommand.execute]
  /// function to be stored for execution.
  EditorCommandFunction(this._execute);

  final void Function(Document, DocumentEditorTransaction) _execute;

  @override
  void execute(Document document, DocumentEditorTransaction transaction) {
    _execute(document, transaction);
  }
}

/// Accumulates changes to a document to facilitate editing actions.
class DocumentEditorTransaction {
  DocumentEditorTransaction._(
    MutableDocument document,
  ) : _document = document;

  final MutableDocument _document;

  /// Inserts the given [node] into the [Document] at the given [index].
  void insertNodeAt(int index, DocumentNode node) {
    _document.insertNodeAt(index, node);
  }

  /// Inserts [newNode] immediately before the given [existingNode].
  void insertNodeBefore({
    required DocumentNode existingNode,
    required DocumentNode newNode,
  }) {
    _document.insertNodeBefore(existingNode: existingNode, newNode: newNode);
  }

  /// Inserts [newNode] immediately after the given [existingNode].
  void insertNodeAfter({
    required DocumentNode existingNode,
    required DocumentNode newNode,
  }) {
    _document.insertNodeAfter(existingNode: existingNode, newNode: newNode);
  }

  /// Deletes the node at the given [index].
  void deleteNodeAt(int index) {
    _document.deleteNodeAt(index);
  }

  /// Moves a [DocumentNode] matching the given [nodeId] from its current index
  /// in the [Document] to the given [targetIndex].
  ///
  /// If none of the nodes in this document match [nodeId], throws an error.
  void moveNode({required String nodeId, required int targetIndex}) {
    _document.moveNode(nodeId: nodeId, targetIndex: targetIndex);
  }

  /// Replaces the given [oldNode] with the given [newNode]
  void replaceNode({
    required DocumentNode oldNode,
    required DocumentNode newNode,
  }) {
    _document.replaceNode(oldNode: oldNode, newNode: newNode);
  }

  /// Deletes the given [node] from the [Document].
  bool deleteNode(DocumentNode node) {
    return _document.deleteNode(node);
  }
}

/// An in-memory, mutable [Document].
class MutableDocument with ChangeNotifier implements Document {
  /// Creates an in-memory, mutable version of a [Document].
  ///
  /// Initializes the content of this [MutableDocument] with the given [nodes],
  /// if provided, or empty content otherwise.
  MutableDocument({
    List<DocumentNode>? nodes,
  }) : _nodes = nodes ?? [] {
    // Register listeners for all initial nodes.
    for (final node in _nodes) {
      node.addListener(_forwardNodeChange);
    }
  }

  final List<DocumentNode> _nodes;
  final Map<String, int> _nodeIndexCache = HashMap();

  @override
  List<DocumentNode> get nodes => _nodes;

  @override
  DocumentNode? getNodeById(String nodeId) {
    if (_nodeIndexCache.containsKey(nodeId)) {
      return _nodes[_nodeIndexCache[nodeId]!];
    }
    final index = _nodes.indexWhere(
      (element) => element.id == nodeId,
    );
    if (index < 0) return null;
    _nodeIndexCache[nodeId] = index;
    return _nodes[index];
  }

  @override
  DocumentNode? getNodeAt(int index) {
    if (index < 0 || index >= _nodes.length) {
      return null;
    }

    return _nodes[index];
  }

  @override
  int getNodeIndex(DocumentNode node) {
    final index = getNodeIndexById(node.id);
    if (index < 0) return -1;
    if (_nodes[index] == node) return index;
    return -1;
  }

  @override
  int getNodeIndexById(String nodeId) {
    final cachedIndex = _nodeIndexCache[nodeId];
    if (cachedIndex != null) return cachedIndex;
    final index = _nodes.indexWhere((node) => node.id == nodeId);
    if (index < 0) return -1;
    _nodeIndexCache[nodeId] = index;
    return index;
  }

  @override
  DocumentNode? getNodeBefore(DocumentNode node) {
    final nodeIndex = getNodeIndex(node);
    return nodeIndex > 0 ? getNodeAt(nodeIndex - 1) : null;
  }

  @override
  DocumentNode? getNodeAfter(DocumentNode node) {
    final nodeIndex = getNodeIndex(node);
    return nodeIndex >= 0 && nodeIndex < _nodes.length - 1 ? getNodeAt(nodeIndex + 1) : null;
  }

  @override
  DocumentNode? getNode(DocumentPosition position) {
    final index = getNodeIndexById(position.nodeId);
    if (index < 0) return null;
    return _nodes[index];
  }

  @override
  DocumentRange getRangeBetween(DocumentPosition position1, DocumentPosition position2) {
    late TextAffinity affinity = getAffinityBetween(base: position1, extent: position2);
    return DocumentRange(
      start: affinity == TextAffinity.downstream ? position1 : position2,
      end: affinity == TextAffinity.downstream ? position2 : position1,
    );
  }

  @override
  List<DocumentNode> getNodesInside(DocumentPosition position1, DocumentPosition position2) {
    final index1 = getNodeIndexById(position1.nodeId);
    if (index1 < 0) {
      throw Exception('No such position in document: $position1');
    }

    final index2 = getNodeIndexById(position2.nodeId);
    if (index2 < 0) {
      throw Exception('No such position in document: $position2');
    }

    final from = min(index1, index2);
    final to = max(index1, index2);

    return _nodes.sublist(from, to + 1);
  }

  /// Inserts the given [node] into the [Document] at the given [index].
  void insertNodeAt(int index, DocumentNode node) {
    if (index <= _nodes.length) {
      _nodes.insert(index, node);
      node.addListener(_forwardNodeChange);
      _nodeIndexCache.clear();
      notifyListeners();
    }
  }

  /// Inserts [newNode] immediately before the given [existingNode].
  void insertNodeBefore({
    required DocumentNode existingNode,
    required DocumentNode newNode,
  }) {
    final nodeIndex = _nodes.indexOf(existingNode);
    _nodes.insert(nodeIndex, newNode);
    newNode.addListener(_forwardNodeChange);
    _nodeIndexCache.clear();
    notifyListeners();
  }

  /// Inserts [newNode] immediately after the given [existingNode].
  void insertNodeAfter({
    required DocumentNode existingNode,
    required DocumentNode newNode,
  }) {
    final nodeIndex = _nodes.indexOf(existingNode);
    if (nodeIndex >= 0 && nodeIndex < _nodes.length) {
      _nodes.insert(nodeIndex + 1, newNode);
      newNode.addListener(_forwardNodeChange);
      _nodeIndexCache.clear();
      notifyListeners();
    }
  }

  /// Deletes the node at the given [index].
  void deleteNodeAt(int index) {
    if (index >= 0 && index < _nodes.length) {
      final removedNode = _nodes.removeAt(index);
      removedNode.removeListener(_forwardNodeChange);
      _nodeIndexCache.clear();
      notifyListeners();
    } else {
      editorDocLog.warning('Could not delete node. Index out of range: $index');
    }
  }

  /// Deletes the given [node] from the [Document].
  bool deleteNode(DocumentNode node) {
    node.removeListener(_forwardNodeChange);
    final index = getNodeIndex(node);
    if (index >= 0) {
      _nodes.removeAt(index);
      _nodeIndexCache.clear();
    }

    notifyListeners();

    return index >= 0;
  }

  /// Moves a [DocumentNode] matching the given [nodeId] from its current index
  /// in the [Document] to the given [targetIndex].
  ///
  /// If none of the nodes in this document match [nodeId], throws an error.
  void moveNode({required String nodeId, required int targetIndex}) {
    final nodeIndex = getNodeIndexById(nodeId);
    if (nodeIndex < 0) {
      throw Exception('Could not find node with nodeId: $nodeId');
    }

    _nodes.insert(targetIndex, _nodes.removeAt(nodeIndex));
    _nodeIndexCache.clear();
    notifyListeners();
  }

  /// Replaces the given [oldNode] with the given [newNode]
  void replaceNode({
    required DocumentNode oldNode,
    required DocumentNode newNode,
  }) {
    final index = getNodeIndex(oldNode);

    if (index != -1) {
      oldNode.removeListener(_forwardNodeChange);
      _nodes.removeAt(index);

      newNode.addListener(_forwardNodeChange);
      try {
        _nodes.insert(index, newNode);
      } catch (e) {
        print(e);
      }

      _nodeIndexCache.clear();
      notifyListeners();
    } else {
      throw Exception('Could not find oldNode: ${oldNode.id}');
    }
  }

  void _forwardNodeChange() {
    notifyListeners();
  }

  /// Returns [true] if the content of the [other] [Document] is equivalent
  /// to the content of this [Document].
  ///
  /// Content equivalency compares types of content nodes, and the content
  /// within them, like the text of a paragraph, but ignores node IDs and
  /// ignores the runtime type of the [Document], itself.
  @override
  bool hasEquivalentContent(Document other) {
    if (_nodes.length != other.nodes.length) {
      return false;
    }

    for (int i = 0; i < _nodes.length; ++i) {
      if (!_nodes[i].hasEquivalentContent(other.nodes[i])) {
        return false;
      }
    }

    return true;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MutableDocument &&
          runtimeType == other.runtimeType &&
          const DeepCollectionEquality().equals(_nodes, other.nodes);

  @override
  int get hashCode => _nodes.hashCode;
}
