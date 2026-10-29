import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/adb/adb_models.dart';
import '../core/log/log_service.dart';
import '../services/app_services.dart';
import '../ui/format.dart';
import 'connection_controller.dart';

enum BrowseViewId { recents, screenshots, downloads, camera, folder }

enum SortMode { dateDesc, dateAsc, nameAsc, nameDesc, sizeDesc }

enum GroupMode { none, day, ext }

@immutable
class BrowseLocation {
  final BrowseViewId id;
  final String title;
  final IconData icon;
  final List<String> paths; // merged sources

  const BrowseLocation(this.id, this.title, this.icon, this.paths);

  static const recents = BrowseLocation(
      BrowseViewId.recents, 'Recent Files', Icons.schedule, []);
  static const screenshots = BrowseLocation(
      BrowseViewId.screenshots,
      'Screenshots',
      Icons.crop_free,
      ['/sdcard/DCIM/Screenshots', '/sdcard/Pictures/Screenshots', '/sdcard/DCIM/VideoCaptures']);
  static const downloads =
      BrowseLocation(BrowseViewId.downloads, 'Downloads', Icons.download, ['/sdcard/Download']);
  static const camera =
      BrowseLocation(BrowseViewId.camera, 'Camera', Icons.photo_camera, ['/sdcard/DCIM/Camera']);

  static BrowseLocation deviceFolder(String path) => BrowseLocation(
      BrowseViewId.folder,
      path.split('/').where((s) => s.isNotEmpty).last,
      Icons.folder_open,
      [path]);
}

/// One segment of the path bar. [path] is null for the segment you are
/// already standing on; [isMerge] marks a sibling source rather than a child
/// (a preset like Screenshots reads from several folders at once), which
/// changes the separator that precedes it.
@immutable
class PathCrumb {
  final String label;
  final String? path;
  final bool isMerge;
  const PathCrumb(this.label, {this.path, this.isMerge = false});
}

/// One grouped row for the list view: either a header or a file.
@immutable
class BrowserRow {
  final String? header;
  final int? headerCount;
  final PhoneFile? file;
  const BrowserRow.header(this.header, {this.headerCount}) : file = null;
  const BrowserRow.fileRow(PhoneFile this.file) : header = null, headerCount = null;
}

/// SSOT for the file browser: current location, entries, sort/group/search,
/// selection and pagination. The UI is a pure projection of this state.
class BrowserController extends ChangeNotifier {
  BrowserController._();
  static final BrowserController instance = BrowserController._();

  static const _pageSize = 60;
  static const _cacheCap = 12;

  BrowseLocation _location = BrowseLocation.recents;
  List<PhoneFile> _entries = const [];
  bool _loading = false;
  String? _error;
  SortMode _sort = SortMode.dateDesc;
  GroupMode _group = GroupMode.day;
  String _query = '';
  final Set<String> _selection = {};
  int _visibleCount = _pageSize;
  List<String> _deviceFolders = const [];
  Timer? _poll;
  int _generation = 0;
  bool _refreshing = false;
  DateTime? _lastListedAt;

  /// Per-location listing cache (stale-while-revalidate). Keys are LRU-ordered
  /// in [_cacheOrder]; the silent poll keeps every cached listing diffed
  /// against the device, so deletions and removals are evicted from the cache
  /// the same tick they're detected.
  final Map<String, List<PhoneFile>> _cache = {};
  final List<String> _cacheOrder = [];

  BrowseLocation get location => _location;
  bool get loading => _loading;
  String? get error => _error;
  SortMode get sort => _sort;
  GroupMode get group => _group;
  String get query => _query;
  int get visibleCount => _visibleCount;
  List<String> get deviceFolders => _deviceFolders;
  Set<String> get selection => _selection;
  int get selectedCount => _selection.length;
  bool get hasMore => _visibleCount < _filtered.length;
  List<PhoneFile> get entries => _entries;
  DateTime? get lastListedAt => _lastListedAt;

  final List<PhoneFile> _filtered = [];

  /// Rows to render: headers (when grouping) + up to [visibleCount] files.
  List<BrowserRow> buildRows() {
    final rows = <BrowserRow>[];
    if (_group == GroupMode.none) {
      for (final f in _filtered.take(_visibleCount)) {
        rows.add(BrowserRow.fileRow(f));
      }
      return rows;
    }
    // Full-list counts so headers show how big each group is even when the
    // visible page cuts it off.
    final counts = <String, int>{};
    for (final f in _filtered) {
      final key = _groupKey(f);
      counts[key] = (counts[key] ?? 0) + 1;
    }
    var shown = 0;
    String? lastKey;
    for (final f in _filtered) {
      if (shown >= _visibleCount) break;
      final key = _groupKey(f);
      if (key != lastKey) {
        rows.add(BrowserRow.header(key, headerCount: counts[key]));
        lastKey = key;
      }
      rows.add(BrowserRow.fileRow(f));
      shown++;
    }
    return rows;
  }

  String _groupKey(PhoneFile f) {
    switch (_group) {
      case GroupMode.none:
        return '';
      case GroupMode.day:
        return f.modified.dateGroupLabel;
      case GroupMode.ext:
        final e = f.ext;
        return e.isEmpty ? 'No extension' : e.toUpperCase();
    }
  }

  String _keyFor(BrowseLocation loc) =>
      loc.id == BrowseViewId.folder ? 'folder:${loc.paths.first}' : loc.id.name;

  void _cachePut(BrowseLocation loc, List<PhoneFile> files) {
    final key = _keyFor(loc);
    _cache[key] = files;
    _cacheOrder
      ..remove(key)
      ..insert(0, key);
    while (_cacheOrder.length > _cacheCap) {
      _cache.remove(_cacheOrder.removeLast());
    }
  }

  // ------------------------------------------------------------- mutations

  void setSort(SortMode mode) {
    if (mode == _sort) return;
    _sort = mode;
    _recompute();
  }

  void setGroup(GroupMode mode) {
    if (mode == _group) return;
    _group = mode;
    _recompute();
  }

  void setQuery(String q) {
    _query = q;
    _visibleCount = _pageSize;
    _recompute();
  }

  void loadMore() {
    if (!hasMore) return;
    _visibleCount += _pageSize;
    notifyListeners();
  }

  void toggleSelect(String path) {
    if (!_selection.remove(path)) _selection.add(path);
    notifyListeners();
  }

  void selectAllVisible() {
    for (final f in _filtered.take(_visibleCount)) {
      _selection.add(f.path);
    }
    notifyListeners();
  }

  void clearSelection() {
    if (_selection.isEmpty) return;
    _selection.clear();
    notifyListeners();
  }

  List<PhoneFile> get selectedFiles =>
      _filtered.where((f) => _selection.contains(f.path)).toList();

  /// The folder a push lands in: whatever is open in Browse when it is a
  /// single real path, otherwise Download. A merged view (Screenshots reads
  /// three folders) and Recent Files have no one folder to write to.
  String get pushTarget {
    final paths = _location.paths;
    return paths.length == 1 ? paths.first : '/sdcard/Download';
  }

  /// Segments for the path bar. The final segment carries a null path —
  /// that is where we already are; every earlier one navigates. A preset
  /// with no single path (Recent Files) reports only its own title, and a
  /// merged preset lists its source folders as siblings.
  List<PathCrumb> get pathCrumbs {
    final loc = _location;
    if (loc.paths.length == 1) {
      final segs =
          loc.paths.first.split('/').where((s) => s.isNotEmpty).toList();
      if (segs.isEmpty) return [PathCrumb(loc.title)];
      final crumbs = <PathCrumb>[];
      var acc = '';
      for (var i = 0; i < segs.length; i++) {
        acc = '$acc/${segs[i]}';
        // The first segment opens the path — spell the slash so it reads as
        // a path rather than as a folder name.
        crumbs.add(PathCrumb(
          i == 0 ? '/${segs[i]}' : segs[i],
          path: i == segs.length - 1 ? null : acc,
        ));
      }
      return crumbs;
    }
    if (loc.paths.isEmpty) return [PathCrumb(loc.title)];
    return [
      PathCrumb(loc.title),
      for (final p in loc.paths) PathCrumb(p, path: p, isMerge: true),
    ];
  }

  /// The containing folder of the current location, or null at its top.
  String? get parentPath {
    final paths = _location.paths;
    if (paths.length != 1) return null;
    final path = paths.first;
    final i = path.lastIndexOf('/');
    if (i <= 0) return null;
    final parent = path.substring(0, i);
    return parent.isEmpty ? null : parent;
  }

  /// Navigate into one folder on the device.
  Future<void> openPath(String path) =>
      openLocation(BrowseLocation.deviceFolder(path));

  Future<void> openLocation(BrowseLocation loc, {bool force = false}) async {
    if (!force && identical(loc, _location) && _entries.isNotEmpty) return;
    final sameLocation =
        loc.id == _location.id && listEquals(loc.paths, _location.paths);
    _location = loc;
    if (!sameLocation) _query = '';
    _visibleCount = _pageSize;
    _selection.clear();
    final cached = force ? null : _cache[_keyFor(loc)];
    if (cached != null) {
      // Stale-while-revalidate: paint the cached listing instantly (no flash
      // of the previous workspace, no spinner), then revalidate silently.
      _entries = cached;
      _filtered
        ..clear()
        ..addAll(_applyFilter(cached));
      _loading = false;
      _error = null;
      notifyListeners();
      await refresh(silent: true);
    } else {
      // No cache for this workspace — never let the previous one linger.
      _entries = const [];
      _filtered.clear();
      _error = null;
      _loading = true;
      notifyListeners();
      await refresh(logChange: true);
    }
  }

  /// Reloads the current location. [silent] polls re-list without flashing
  /// the loading state, and only notify when content actually changed.
  ///
  /// A silent poll never restarts an in-flight load — a folder that takes
  /// longer than one poll interval would otherwise be superseded every tick
  /// and never finish (the eternal-spinner bug).
  Future<void> refresh({bool logChange = false, bool silent = false}) async {
    if (!ConnectionController.instance.isConnected) {
      _entries = const [];
      _filtered.clear();
      _error = null;
      _loading = false;
      notifyListeners();
      return;
    }
    if (_refreshing && silent) return;
    _refreshing = true;
    final gen = ++_generation;
    if (!silent) {
      _loading = true;
      _error = null;
      notifyListeners();
    }
    final loc = _location;
    final log = Services.log;
    try {
      final List<PhoneFile> result;
      if (loc.id == BrowseViewId.recents) {
        result = await Services.adb.listRecents();
      } else if (loc.paths.length == 1) {
        result = await Services.adb.listDir(loc.paths.first);
      } else {
        final merged = <PhoneFile>[];
        for (final p in loc.paths) {
          merged.addAll(await Services.adb.listDir(p));
        }
        result = merged;
      }
      if (gen != _generation) return; // superseded by a newer load
      _sortList(result);
      _cachePut(loc, result);
      final changed = _differs(_entries, result);
      _entries = result;
      _lastListedAt = DateTime.now();
      _filtered
        ..clear()
        ..addAll(_applyFilter(result));
      _loading = false;
      if (logChange) {
        log.browse(LogLevel.info,
            'Listed ${loc.title} — ${result.length} item${result.length == 1 ? '' : 's'}');
      } else if (silent && changed) {
        log.browse(LogLevel.info,
            'Live refresh: ${loc.title} changed (${result.length} items)');
      }
      if (!silent || changed) notifyListeners();
    } catch (e) {
      if (gen != _generation) return;
      _loading = false;
      _error = e.toString();
      log.browse(LogLevel.error, 'Failed to list ${loc.title} — $e');
      notifyListeners();
    } finally {
      // Only the load that owns the current generation releases the gate.
      if (gen == _generation) _refreshing = false;
    }
  }

  bool _differs(List<PhoneFile> a, List<PhoneFile> b) {
    if (a.length != b.length) return true;
    for (var i = 0; i < a.length; i++) {
      if (a[i].path != b[i].path ||
          a[i].size != b[i].size ||
          a[i].modified != b[i].modified) {
        return true;
      }
    }
    return false;
  }

  void _sortList(List<PhoneFile> list) {
    switch (_sort) {
      case SortMode.dateDesc:
        list.sort((a, b) => b.modified.compareTo(a.modified));
      case SortMode.dateAsc:
        list.sort((a, b) => a.modified.compareTo(b.modified));
      case SortMode.nameAsc:
        list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      case SortMode.nameDesc:
        list.sort((a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()));
      case SortMode.sizeDesc:
        list.sort((a, b) => b.size.compareTo(a.size));
    }
  }

  List<PhoneFile> _applyFilter(List<PhoneFile> list) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return List.of(list);
    return list
        .where((f) => f.name.toLowerCase().contains(q))
        .toList(growable: false);
  }

  void _recompute() {
    _sortList(_entries);
    _filtered
      ..clear()
      ..addAll(_applyFilter(_entries));
    notifyListeners();
  }

  // ------------------------------------------------------ folder discovery

  Future<void> loadDeviceFolders() async {
    if (!ConnectionController.instance.isConnected) return;
    final folders = await Services.adb.sdcardFolders();
    if (!listEquals(folders, _deviceFolders)) {
      _deviceFolders = folders;
      notifyListeners();
    }
  }

  // ------------------------------------------------------------- lifecycle

  /// Live poll while connected. Deliberately cheap: one name-only round trip
  /// that diffs against the current listing. Only when the file set actually
  /// changed (file deleted, added, renamed) does a full stat refresh run —
  /// so deletions surface within one poll tick without hammering the device.
  void startPolling() {
    _poll?.cancel();
    final seconds = Services.config.pollIntervalSeconds.clamp(2, 60);
    _poll = Timer.periodic(Duration(seconds: seconds), (_) {
      if (!ConnectionController.instance.isConnected) return;
      if (_deviceFolders.isEmpty) loadDeviceFolders();
      // Every 6th tick do a full stat refresh so in-place modifications
      // (same name, new size/mtime) can't linger stale; the rest are cheap
      // name-only diffs tuned for fast delete/add detection.
      if (++_tick % 6 == 0) {
        refresh(silent: true);
      } else {
        _liteCheck();
      }
    });
  }

  int _tick = 0;

  Future<void> _liteCheck() async {
    if (_refreshing || _loading) return;
    final loc = _location;
    final Set<String> fresh;
    if (loc.id == BrowseViewId.recents) {
      fresh = (await Services.adb.listRecentPaths()).toSet();
    } else {
      // Directories: names only — compare against entry basenames.
      final names = <String>{};
      for (final p in loc.paths) {
        names.addAll((await Services.adb.listNames(p))
            .where((n) => !n.startsWith('ls:') && n != 'opendir failed'));
      }
      fresh = names;
    }
    final current = loc.id == BrowseViewId.recents
        ? _entries.map((f) => f.path).toSet()
        : _entries.map((f) => f.name).toSet();
    if (fresh.length == current.length && fresh.containsAll(current)) return;
    await refresh(silent: true);
  }

  void stopPolling() {
    _poll?.cancel();
    _poll = null;
  }

  void onDeviceLost() {
    _generation++;
    _refreshing = false;
    _entries = const [];
    _filtered.clear();
    _selection.clear();
    _deviceFolders = const [];
    _error = null;
    _loading = false;
    invalidateCache();
    notifyListeners();
  }

  /// Drops all cached listings (device changed — listings may no longer match).
  void invalidateCache() {
    _cache.clear();
    _cacheOrder.clear();
  }

  /// Drops cached listings under one device [path] (e.g. after a push wrote
  /// there), so the next visit re-lists instead of showing stale content.
  void invalidatePath(String path) {
    final key = 'folder:$path';
    _cache.remove(key);
    _cacheOrder.remove(key);
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }
}
