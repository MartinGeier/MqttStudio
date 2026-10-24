import 'package:event/event.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/documentation/doc_node_editor_model.dart';
import 'package:mqttstudio/documentation/discover_viewmodel.dart';
import 'package:mqttstudio/documentation/discovery_service.dart';
import 'package:mqttstudio/documentation/doc_root_editor_model.dart';
import 'package:mqttstudio/documentation/documentation_service.dart';
import 'package:mqttstudio/documentation/engine/discovery_merger.dart';
import 'package:mqttstudio/documentation/engine/doc_path.dart';
import 'package:mqttstudio/documentation/engine/doc_tree.dart';
import 'package:mqttstudio/documentation/model/observed_topic.dart';
import 'package:mqttstudio/documentation/model/topic_documentation.dart';
import 'package:mqttstudio/project/project_manager.dart';
import 'package:srx_flutter/srx_flutter.dart';

enum DocFilter { all, undocumented, added, changed, notSeen, draft, stable, deprecated }

// Viewmodel of the documentation tab: the tree, the selection and the editor of the selected node
class DocumentationViewmodel extends SrxChangeNotifier {
  final _service = GetIt.I.get<DocumentationService>();
  final _projectManager = GetIt.I.get<ProjectManager>();
  final _discovery = GetIt.I.get<DiscoveryService>();

  // a discovery result is ready for the review
  void Function(DiscoveryResult result)? onDiscoveryResult;
  void Function(String message)? onDiscoveryError;
  bool _observedPanelOpen = true;

  DocTreeEntry _tree = DocTreeEntry.build([]);
  final Set<String> _collapsed = {};
  // null = the root, the documentation as a whole
  String? _selectedPath;
  String _search = '';
  DocFilter _filter = DocFilter.all;
  DocNodeEditorModel? _editor;
  DocRootEditorModel? _rootEditor;

  DocumentationViewmodel() {
    _service.documentationChangedEvent.subscribe(_onChanged);
    _projectManager.projectOpenedEvent.subscribe(_onProjectChanged);
    _projectManager.projectClosedEvent.subscribe(_onProjectChanged);
    _discovery.stateChangedEvent.subscribe(_onDiscoveryChanged);
    _discovery.statsChangedEvent.subscribe(_onDiscoveryChanged);
    _discovery.resultEvent.subscribe(_onDiscoveryResult);
    _discovery.errorEvent.subscribe(_onDiscoveryError);
    _rebuild();
  }

  @override
  void dispose() {
    _service.documentationChangedEvent.unsubscribe(_onChanged);
    _projectManager.projectOpenedEvent.unsubscribe(_onProjectChanged);
    _projectManager.projectClosedEvent.unsubscribe(_onProjectChanged);
    _discovery.stateChangedEvent.unsubscribe(_onDiscoveryChanged);
    _discovery.statsChangedEvent.unsubscribe(_onDiscoveryChanged);
    _discovery.resultEvent.unsubscribe(_onDiscoveryResult);
    _discovery.errorEvent.unsubscribe(_onDiscoveryError);
    _editor?.dispose();
    _rootEditor?.dispose();
    super.dispose();
  }

  bool get isProjectOpen => _projectManager.isProjectOpen;

  TopicDocumentation? get documentation => _service.documentation;

  DocTreeEntry get tree => _tree;

  String? get selectedPath => _selectedPath;

  DocTreeEntry? get selectedEntry => _selectedPath == null ? _tree : _find(_tree, _selectedPath!);

  DocNodeEditorModel? get editor => _editor;

  DocRootEditorModel? get rootEditor => _rootEditor;

  String get search => _search;

  DocFilter get filter => _filter;

  bool get isFiltered => _search.isNotEmpty || _filter != DocFilter.all;

  int get topicCount => _tree.topicCount;

  int get undocumentedCount => _tree.undocumentedCount;

  List<DocTreeRow> get rows => visibleDocRows(_tree, isExpanded: isExpanded, matches: isFiltered ? _matches : null);

  bool isExpanded(String path) => !_collapsed.contains(path);

  void toggleExpanded(String path) {
    if (!_collapsed.remove(path)) {
      _collapsed.add(path);
    }
    notifyListeners();
  }

  void select(String? path) {
    if (path == _selectedPath) {
      return;
    }
    _selectedPath = path;
    if (path != null) {
      // the ancestors open, so the selection is visible
      for (var parent = DocPath.parentOf(path); parent.isNotEmpty; parent = DocPath.parentOf(parent)) {
        _collapsed.remove(parent);
      }
    }
    _updateEditors();
    notifyListeners();
    // the discovery mark has done its job once the user looked at the topic
    var node = path == null ? null : _service.nodeAt(path);
    if (node != null && node.review != DocReviewState.none) {
      node.review = DocReviewState.none;
      _service.notifyChanged();
    }
  }

  void setSearch(String text) {
    _search = text.trim().toLowerCase();
    notifyListeners();
  }

  void setFilter(DocFilter filter) {
    _filter = filter;
    notifyListeners();
  }

  bool _matches(DocTreeEntry entry) {
    var node = entry.node;
    if (node == null) {
      return false;
    }
    var byFilter = switch (_filter) {
      DocFilter.all => true,
      DocFilter.undocumented => node.isTopic && node.isUndocumented,
      DocFilter.added => node.review == DocReviewState.added,
      DocFilter.changed => node.review == DocReviewState.changed,
      DocFilter.notSeen => node.review == DocReviewState.notSeen,
      DocFilter.draft => node.status == DocStatus.draft,
      DocFilter.stable => node.status == DocStatus.stable,
      DocFilter.deprecated => node.status == DocStatus.deprecated
    };
    if (!byFilter || _search.isEmpty) {
      return byFilter;
    }
    return [node.path, node.title, node.description, ...node.tags].any((text) => text.toLowerCase().contains(_search));
  }

  // ---------- discovery ----------

  DiscoveryState get discoveryState => _discovery.state;

  bool get isDiscovering => _discovery.isRunning;

  DiscoverySource get discoverySource => _discovery.source;

  Duration get discoveryElapsed => _discovery.elapsed;

  int get discoveryMessages => _discovery.messages;

  int get discoveryTopics => _discovery.topicCount;

  int get discoveryNewTopics => _discovery.newTopicCount;

  int get discoveryReconnectAttempt => _discovery.reconnectAttempt;

  double? get discoveryProgress => _discovery.progress;

  DiscoveryResult? get lastDiscoveryResult => _discovery.lastResult;

  bool get canDiscover => isProjectOpen && !isDiscovering;

  // throws when the broker or the recording can't be opened
  Future<void> startDiscovery(DiscoverRequest request) =>
      _discovery.start(request.settings, source: request.source, recording: request.recording);

  Future<void> stopDiscovery() => _discovery.stop();

  void applyDiscovery(DiscoveryResult result) => _discovery.apply(result);

  void _onDiscoveryChanged(EventArgs? _) => notifyListeners();

  void _onDiscoveryResult(EventArgs? _) {
    notifyListeners();
    var result = _discovery.lastResult;
    if (result != null) {
      onDiscoveryResult?.call(result);
    }
  }

  void _onDiscoveryError(DiscoveryErrorEventArgs? args) {
    if (args != null) {
      onDiscoveryError?.call(args.message);
    }
  }

  // ---------- observed panel ----------

  bool get isObservedPanelOpen => _observedPanelOpen;

  void toggleObservedPanel() {
    _observedPanelOpen = !_observedPanelOpen;
    notifyListeners();
  }

  // ---------- editing ----------

  bool isTaken(String path) => _service.conflictOf(path) != null;

  void addNode(DocNode node) {
    _service.addNode(node);
    select(node.path);
  }

  // throws ArgumentError when a new path is invalid or taken
  void movePath(String from, String to) {
    // the selection moves first, the service's change event rebuilds the tree with it
    var selected = _selectedPath;
    if (selected != null && DocPath.isAtOrBelow(selected, from)) {
      _selectedPath = to + selected.substring(from.length);
    }
    try {
      _service.movePath(from, to);
    } catch (_) {
      _selectedPath = selected;
      rethrow;
    }
    if (_collapsed.remove(from)) {
      _collapsed.add(to);
    }
    notifyListeners();
  }

  int countAtOrBelow(String path) => _service.nodesAtOrBelow(path).length;

  void deletePath(String path) {
    if (_selectedPath != null && DocPath.isAtOrBelow(_selectedPath!, path)) {
      _selectedPath = DocPath.parentOf(path).isEmpty ? null : DocPath.parentOf(path);
    }
    _service.deletePath(path);
  }

  void duplicate(DocNode node) => select(_service.duplicate(node).path);

  void setTopic(DocNode node, bool isTopic) => _service.setTopic(node, isTopic);

  DocNode? nodeAt(String path) => _service.nodeAt(path);

  List<DocNode> get topicNodes => _service.nodes.where((node) => node.isTopic).toList();

  void _onChanged(EventArgs? _) {
    _rebuild();
    notifyListeners();
  }

  void _onProjectChanged(EventArgs? _) {
    _selectedPath = null;
    _collapsed.clear();
    _rebuild(force: true);
    notifyListeners();
  }

  void _rebuild({bool force = false}) {
    _tree = DocTreeEntry.build(_service.nodes);
    if (_selectedPath != null && _find(_tree, _selectedPath!) == null) {
      _selectedPath = null;
    }
    _updateEditors(force: force);
  }

  // a new editor when the selection, its node or its kind changed; edits through the editor keep it
  void _updateEditors({bool force = false}) {
    var documentation = _service.documentation;
    if (_selectedPath == null) {
      _editor?.dispose();
      _editor = null;
      if (force || _rootEditor?.documentation != documentation) {
        _rootEditor?.dispose();
        _rootEditor = documentation == null ? null : DocRootEditorModel(documentation);
      }
      return;
    }
    _rootEditor?.dispose();
    _rootEditor = null;
    var node = _service.nodeAt(_selectedPath!);
    var current = _editor;
    var same = current != null &&
        current.path == _selectedPath &&
        (current.node == null || current.node == node) &&
        current.isTopic == (node?.isTopic ?? false);
    if (same && !force) {
      return;
    }
    current?.dispose();
    _editor = DocNodeEditorModel(_selectedPath!, node);
  }

  static DocTreeEntry? _find(DocTreeEntry entry, String path) {
    for (var child in entry.children) {
      if (child.path == path) {
        return child;
      }
      if (path.startsWith('${child.path}/')) {
        return _find(child, path);
      }
    }
    return null;
  }
}
