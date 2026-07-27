import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'models.dart';

class AppStorage {
  static final AppStorage instance = AppStorage._internal();
  AppStorage._internal();

  Directory? _customDir;

  // Files
  static const String _historyFile = 'clipboard_history.json';
  static const String _templatesFile = 'templates.json';
  static const String _peersFile = 'peers.json';
  static const String _categoriesFile = 'categories.json';
  static const String _settingsFile = 'settings.json';

  // In-memory cache
  List<ClipboardItem> _history = [];
  List<CommandTemplate> _templates = [];
  List<SyncPeer> _peers = [];
  List<String> _categories = ['Work', 'Terminal', 'Code', 'Personal'];
  Map<String, dynamic> _settings = {
    'secretTimeoutSeconds': 30,
    'themeMode': 'dark',
    'autoSync': true,
    'deviceName': 'Device',
  };

  void setCustomDirectory(Directory dir) {
    _customDir = dir;
  }

  Future<Directory> getStorageDir() async {
    if (_customDir != null) return _customDir!;
    try {
      final dir = await getApplicationSupportDirectory();
      await dir.create(recursive: true);
      return dir;
    } catch (_) {
      final dir = Directory('.cmdclip_data');
      await dir.create(recursive: true);
      return dir;
    }
  }

  // ─── Initializers ──────────────────────────────────────────────────────────

  Future<void> init() async {
    final dir = await getStorageDir();

    // 1. History
    final hFile = File('${dir.path}/$_historyFile');
    if (await hFile.exists()) {
      try {
        final content = await hFile.readAsString();
        final list = json.decode(content) as List;
        _history = list.map((e) => ClipboardItem.fromJson(e)).toList();
      } catch (_) {
        _history = [];
      }
    }

    // 2. Templates
    final tFile = File('${dir.path}/$_templatesFile');
    if (await tFile.exists()) {
      try {
        final content = await tFile.readAsString();
        final list = json.decode(content) as List;
        _templates = list.map((e) => CommandTemplate.fromJson(e)).toList();
      } catch (_) {
        _templates = [];
      }
    } else {
      // Default templates
      _templates = [
        CommandTemplate(
          id: 't1',
          name: 'SSH Quick Connect',
          template: 'ssh {user}@{host} -p {port=22}',
          description: 'SSH shell access with custom port',
        ),
        CommandTemplate(
          id: 't2',
          name: 'Docker Run Container',
          template: 'docker run -d -p {host_port}:{container_port} --name {name} {image}',
          description: 'Run Docker container in background',
        ),
      ];
      await saveTemplates();
    }

    // 3. Peers
    final pFile = File('${dir.path}/$_peersFile');
    if (await pFile.exists()) {
      try {
        final content = await pFile.readAsString();
        final list = json.decode(content) as List;
        _peers = list.map((e) => SyncPeer.fromJson(e)).toList();
      } catch (_) {
        _peers = [];
      }
    }

    // 4. Categories
    final cFile = File('${dir.path}/$_categoriesFile');
    if (await cFile.exists()) {
      try {
        final content = await cFile.readAsString();
        final list = json.decode(content) as List;
        _categories = list.cast<String>();
      } catch (_) {
        // use defaults
      }
    } else {
      await saveCategories();
    }

    // 5. Settings
    final sFile = File('${dir.path}/$_settingsFile');
    if (await sFile.exists()) {
      try {
        final content = await sFile.readAsString();
        _settings = Map<String, dynamic>.from(json.decode(content));
      } catch (_) {
        // use defaults
      }
    } else {
      // Set default device name based on platform
      _settings['deviceName'] = Platform.localHostname;
      await saveSettings();
    }
  }

  // ─── Save Helpers ──────────────────────────────────────────────────────────

  Future<void> saveHistory() async {
    final dir = await getStorageDir();
    final hFile = File('${dir.path}/$_historyFile');
    await hFile.writeAsString(json.encode(_history.map((e) => e.toJson()).toList()));
  }

  Future<void> saveTemplates() async {
    final dir = await getStorageDir();
    final tFile = File('${dir.path}/$_templatesFile');
    await tFile.writeAsString(json.encode(_templates.map((e) => e.toJson()).toList()));
  }

  Future<void> savePeers() async {
    final dir = await getStorageDir();
    final pFile = File('${dir.path}/$_peersFile');
    await pFile.writeAsString(json.encode(_peers.map((e) => e.toJson()).toList()));
  }

  Future<void> saveCategories() async {
    final dir = await getStorageDir();
    final cFile = File('${dir.path}/$_categoriesFile');
    await cFile.writeAsString(json.encode(_categories));
  }

  Future<void> saveSettings() async {
    final dir = await getStorageDir();
    final sFile = File('${dir.path}/$_settingsFile');
    await sFile.writeAsString(json.encode(_settings));
  }

  // ─── CRUD: Clipboard History ───────────────────────────────────────────────

  List<ClipboardItem> getHistory() {
    // Return history sorted: pinned first, then by timestamp descending
    final List<ClipboardItem> sorted = List.from(_history);
    sorted.sort((a, b) {
      if (a.isPinned && !b.isPinned) return -1;
      if (!a.isPinned && b.isPinned) return 1;
      return b.timestamp.compareTo(a.timestamp);
    });
    return sorted;
  }

  Future<ClipboardItem> addClipboardItem(String content, {String category = '', bool isPinned = false}) async {
    // Remove if content already exists to avoid duplicates
    _history.removeWhere((item) => item.content == content && !item.isPinned);

    final item = ClipboardItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      content: content,
      timestamp: DateTime.now(),
      isPinned: isPinned,
      category: category,
    );
    _history.add(item);
    await saveHistory();
    return item;
  }

  Future<void> deleteClipboardItem(String id) async {
    _history.removeWhere((item) => item.id == id);
    await saveHistory();
  }

  Future<void> togglePin(String id) async {
    final index = _history.indexWhere((item) => item.id == id);
    if (index != -1) {
      final item = _history[index];
      _history[index] = item.copyWith(isPinned: !item.isPinned);
      await saveHistory();
    }
  }

  Future<void> setItemCategory(String id, String category) async {
    final index = _history.indexWhere((item) => item.id == id);
    if (index != -1) {
      _history[index] = _history[index].copyWith(category: category);
      await saveHistory();
    }
  }

  Future<void> clearHistory() async {
    _history.clear();
    await saveHistory();
  }

  // ─── CRUD: Command Templates ───────────────────────────────────────────────

  List<CommandTemplate> getTemplates() => _templates;

  Future<void> addTemplate(String name, String template, String description) async {
    final t = CommandTemplate(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      template: template,
      description: description,
    );
    _templates.add(t);
    await saveTemplates();
  }

  Future<void> deleteTemplate(String id) async {
    _templates.removeWhere((t) => t.id == id);
    await saveTemplates();
  }

  // ─── CRUD: Sync Peers ──────────────────────────────────────────────────────

  List<SyncPeer> getPeers() => _peers;

  Future<void> addOrUpdatePeer(String ip, int port, String name, {bool isPaired = true}) async {
    final index = _peers.indexWhere((p) => p.ip == ip && p.port == port);
    if (index != -1) {
      _peers[index] = _peers[index].copyWith(
        name: name,
        isPaired: isPaired,
        lastSynced: DateTime.now(),
      );
    } else {
      _peers.add(SyncPeer(
        ip: ip,
        port: port,
        name: name,
        isPaired: isPaired,
        lastSynced: DateTime.now(),
      ));
    }
    await savePeers();
  }

  Future<void> removePeer(String ip, int port) async {
    _peers.removeWhere((p) => p.ip == ip && p.port == port);
    await savePeers();
  }

  // ─── CRUD: Categories ──────────────────────────────────────────────────────

  List<String> getCategories() => _categories;

  Future<void> addCategory(String category) async {
    final name = category.trim();
    if (name.isNotEmpty && !_categories.contains(name)) {
      _categories.add(name);
      await saveCategories();
    }
  }

  Future<void> deleteCategory(String category) async {
    _categories.remove(category);
    // Unassign category from history items
    for (int i = 0; i < _history.length; i++) {
      if (_history[i].category == category) {
        _history[i] = _history[i].copyWith(category: '');
      }
    }
    await saveHistory();
    await saveCategories();
  }

  // ─── Settings ──────────────────────────────────────────────────────────────

  int get secretTimeoutSeconds => _settings['secretTimeoutSeconds'] as int? ?? 30;
  String get themeMode => _settings['themeMode'] as String? ?? 'dark';
  bool get autoSync => _settings['autoSync'] as bool? ?? true;
  String get deviceName => _settings['deviceName'] as String? ?? 'Device';

  Future<void> updateSetting(String key, dynamic value) async {
    _settings[key] = value;
    await saveSettings();
  }

  // ─── Export / Import ───────────────────────────────────────────────────────

  String exportToJson() {
    return json.encode(_history.map((e) => e.toJson()).toList());
  }

  String exportToCsv() {
    final buffer = StringBuffer();
    // Header
    buffer.writeln('"id","timestamp","isPinned","category","content"');
    for (final item in _history) {
      final escapedContent = item.content.replaceAll('"', '""');
      final escapedCategory = item.category.replaceAll('"', '""');
      buffer.writeln('"${item.id}","${item.timestamp.toIso8601String()}","${item.isPinned}","${escapedCategory}","${escapedContent}"');
    }
    return buffer.toString();
  }

  Future<int> importFromJson(String jsonText) async {
    try {
      final list = json.decode(jsonText) as List;
      final importedItems = list.map((e) => ClipboardItem.fromJson(e)).toList();
      int count = 0;
      for (final item in importedItems) {
        if (!_history.any((existing) => existing.content == item.content)) {
          _history.add(item);
          count++;
        }
      }
      if (count > 0) {
        await saveHistory();
      }
      return count;
    } catch (_) {
      throw const FormatException('Invalid JSON format.');
    }
  }

  Future<int> importFromCsv(String csvText) async {
    try {
      final List<ClipboardItem> importedItems = [];
      final List<String> fields = [];
      final StringBuffer currentField = StringBuffer();
      bool inQuotes = false;
      int i = 0;

      while (i < csvText.length) {
        final char = csvText[i];
        if (char == '"') {
          if (inQuotes && i + 1 < csvText.length && csvText[i + 1] == '"') {
            currentField.write('"');
            i += 2;
            continue;
          }
          inQuotes = !inQuotes;
          i++;
        } else if (char == ',' && !inQuotes) {
          fields.add(currentField.toString());
          currentField.clear();
          i++;
        } else if ((char == '\n' || char == '\r') && !inQuotes) {
          if (char == '\r' && i + 1 < csvText.length && csvText[i + 1] == '\n') {
            i++;
          }
          fields.add(currentField.toString());
          currentField.clear();
          if (fields.isNotEmpty && fields[0] != 'id') { // Skip header
            if (fields.length >= 5) {
              importedItems.add(ClipboardItem(
                id: fields[0],
                timestamp: DateTime.tryParse(fields[1]) ?? DateTime.now(),
                isPinned: fields[2].toLowerCase() == 'true',
                category: fields[3],
                content: fields[4],
              ));
            }
          }
          fields.clear();
          i++;
        } else {
          currentField.write(char);
          i++;
        }
      }

      if (fields.isNotEmpty || currentField.isNotEmpty) {
        fields.add(currentField.toString());
        if (fields.isNotEmpty && fields[0] != 'id' && fields.length >= 5) {
          importedItems.add(ClipboardItem(
            id: fields[0],
            timestamp: DateTime.tryParse(fields[1]) ?? DateTime.now(),
            isPinned: fields[2].toLowerCase() == 'true',
            category: fields[3],
            content: fields[4],
          ));
        }
      }

      int count = 0;
      for (final item in importedItems) {
        if (!_history.any((existing) => existing.content == item.content)) {
          _history.add(item);
          count++;
        }
      }
      if (count > 0) {
        await saveHistory();
      }
      return count;
    } catch (_) {
      throw const FormatException('Invalid CSV format.');
    }
  }
}
