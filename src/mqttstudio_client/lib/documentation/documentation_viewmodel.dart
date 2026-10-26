import 'dart:convert';
import 'dart:io';
import 'package:event/event.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:mqttstudio/documentation/doc_node_editor_model.dart';
import 'package:mqttstudio/documentation/check_service.dart';
import 'package:mqttstudio/documentation/discover_viewmodel.dart';
import 'package:mqttstudio/documentation/discovery_service.dart';
import 'package:mqttstudio/documentation/doc_root_editor_model.dart';
import 'package:mqttstudio/documentation/documentation_service.dart';
import 'package:mqttstudio/documentation/engine/discovery_merger.dart';
import 'package:mqttstudio/documentation/engine/doc_path.dart';
import 'package:mqttstudio/documentation/engine/conformance_checker.dart';
import 'package:mqttstudio/documentation/engine/doc_tree.dart';
import 'package:mqttstudio/documentation/export/csv_exporter.dart';
import 'package:mqttstudio/documentation/export/doc_export.dart';
import 'package:mqttstudio/documentation/export_viewmodel.dart';
import 'package:mqttstudio/documentation/import_viewmodel.dart';
import 'package:mqttstudio/documentation/model/observed_topic.dart';
import 'package:mqttstudio/documentation/model/topic_documentation.dart';
import 'package:mqttstudio/documentation/engine/simulation_builder.dart';
import 'package:mqttstudio/project/project_manager.dart';
import 'package:mqttstudio/simulator/simulator.dart';
import 'package:srx_flutter/srx_flutter.dart';

enum DocFilter { all, undocumented, added, changed, notSeen, withFindings, draft, stable, deprecated }

// Viewmodel of the documentation tab: the tree, the selection and the editor of the selected node
class DocumentationViewmodel extends SrxChangeNotifier {
  final _service = GetIt.I.get<DocumentationService>();
  final _projectManager = GetIt.I.get<ProjectManager>();
  final _discovery = GetIt.I.get<DiscoveryService>();
  final _check = GetIt.I.get<CheckService>();

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
    _service.discoverRequestedEvent.subscribe(_onDiscoverRequested);
    _projectManager.projectOpenedEvent.subscribe(_onProjectChanged);
    _projectManager.projectClosedEvent.subscribe(_onProjectChanged);
    _discovery.stateChangedEvent.subscribe(_onDiscoveryChanged);
    _discovery.statsChangedEvent.subscribe(_onDiscoveryChanged);
    _discovery.resultEvent.subscribe(_onDiscoveryResult);
    _discovery.errorEvent.subscribe(_onDiscoveryError);
    _check.stateChangedEvent.subscribe(_onDiscoveryChanged);
    _check.statsChangedEvent.subscribe(_onDiscoveryChanged);
    _check.errorEvent.subscribe(_onCheckError);
    _rebuild();
  }

  @override
  void dispose() {
    _service.documentationChangedEvent.unsubscribe(_onChanged);
    _service.discoverRequestedEvent.unsubscribe(_onDiscoverRequested);
    _projectManager.projectOpenedEvent.unsubscribe(_onProjectChanged);
    _projectManager.projectClosedEvent.unsubscribe(_onProjectChanged);
    _discovery.stateChangedEvent.unsubscribe(_onDiscoveryChanged);
    _discovery.statsChangedEvent.unsubscribe(_onDiscoveryChanged);
    _discovery.resultEvent.unsubscribe(_onDiscoveryResult);
    _discovery.errorEvent.unsubscribe(_onDiscoveryError);
    _check.stateChangedEvent.unsubscribe(_onDiscoveryChanged);
    _check.statsChangedEvent.unsubscribe(_onDiscoveryChanged);
    _check.errorEvent.unsubscribe(_onCheckError);
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
      DocFilter.withFindings => severityOf(node.path) != null,
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

  bool get canDiscover => isProjectOpen && !isDiscovering && !isChecking;

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

  // ---------- export and import ----------

  // the file name the export was saved as, null when the user cancelled
  Future<String?> exportDocumentation(DocExportRequest request) async {
    var documentation = _service.documentation!;
    var text = DocExport.run(documentation, request.options, broker: _projectManager.currentProject?.mqttSettings);
    return _saveText(request.fileName, text);
  }

  // the findings as CSV; the file name or path, null when the user cancelled
  Future<String?> exportFindings() => _saveText('findings.csv', findingsCsv());

  // the browser downloads the bytes, the desktop asks where to write them
  static Future<String?> _saveText(String fileName, String text) async {
    var bytes = Uint8List.fromList(utf8.encode(text));
    var extension = fileName.substring(fileName.lastIndexOf('.') + 1);
    var path = await FilePicker.saveFile(
        fileName: fileName, type: FileType.custom, allowedExtensions: [extension], bytes: kIsWeb ? bytes : null);
    if (kIsWeb) {
      return fileName;
    }
    if (path == null) {
      return null;
    }
    await File(path).writeAsBytes(bytes);
    return path;
  }

  void importDocumentation(DocImportRequest request) {
    request.plan.applyTo(_service.documentation!, replaceAll: request.replaceAll);
    if (_selectedPath != null && _service.nodeAt(_selectedPath!) == null) {
      _selectedPath = null;
    }
    _service.notifyChanged();
  }

  // ---------- conformance check ----------

  CheckState get checkState => _check.state;

  bool get isChecking => _check.isRunning;

  bool get canCheck => isProjectOpen && !isDiscovering && !isChecking && topicCount > 0;

  Duration get checkElapsed => _check.elapsed;

  int get checkMessages => _check.messages;

  int get checkReconnectAttempt => _check.reconnectAttempt;

  List<String> get checkFilters => _check.filters;

  // the findings of the running or last check, null when there are none to show
  List<Finding>? get findings => _check.checker?.findings;

  int findingCount(FindingSeverity severity) => _check.checker?.countOf(severity) ?? 0;

  FindingSeverity? severityOf(String path) => _check.checker?.severityByPath[path];

  // throws when the broker can't be reached. With a branch only the documented topics at or below it are checked and
  // listened to.
  Future<void> startCheck({String? branch}) async {
    if (branch == null) {
      await _check.start();
      return;
    }
    var documentation = _service.documentation!;
    await _check.start(
        documentation: TopicDocumentation(
            title: documentation.title,
            nodes: _service.nodesAtOrBelow(branch),
            ignoreFilters: documentation.ignoreFilters));
  }

  void stopCheck() => _check.stop();

  void clearFindings() => _check.clear();

  // empties the findings and keeps checking
  void restartFindings() => _check.clearFindings();

  String findingsCsv() => CsvExporter.findings(findings ?? []);

  void Function(String message)? onCheckError;

  // the recorder tab asked to discover a recording; the page opens the discover dialog
  void Function(String recordingId)? onDiscoverRequested;

  void _onDiscoverRequested(DocDiscoverEventArgs? args) {
    if (args != null) {
      onDiscoverRequested?.call(args.recordingId);
    }
  }

  void _onCheckError(CheckErrorEventArgs? args) {
    if (args != null) {
      onCheckError?.call(args.message);
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

  int get nodeCount => _service.nodes.length;

  void clearAll() {
    _selectedPath = null;
    _service.clearAll();
  }

  int topicCountAtOrBelow(String path) => _service.nodesAtOrBelow(path).where((node) => node.isTopic).length;

  // a simulated device per documented topic at or below the path (doc/documentation-design.md §8.2); returns their names
  List<String> createSimulation(String path) {
    var simulator = GetIt.I.get<Simulator>();
    return [
      for (var node in _service.nodesAtOrBelow(path).where((node) => node.isTopic))
        simulator
            .addDevice(SimulationBuilder.deviceOf(node,
                simulator.uniqueNewDeviceName(node.title.isNotEmpty ? node.title : DocPath.lastSegmentOf(node.path))))
            .name
    ];
  }

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
