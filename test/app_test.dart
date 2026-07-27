import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:cmdclip/models.dart';
import 'package:cmdclip/storage.dart';
import 'package:cmdclip/secret_manager.dart';
import 'package:cmdclip/sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Models Unit Tests', () {
    test('ClipboardItem serialization and deserialization', () {
      final now = DateTime.now();
      final item = ClipboardItem(
        id: '123',
        content: 'echo "hello"',
        timestamp: now,
        isPinned: true,
        category: 'Code',
      );

      final jsonMap = item.toJson();
      expect(jsonMap['id'], '123');
      expect(jsonMap['content'], 'echo "hello"');
      expect(jsonMap['isPinned'], true);
      expect(jsonMap['category'], 'Code');

      final deserialized = ClipboardItem.fromJson(jsonMap);
      expect(deserialized.id, '123');
      expect(deserialized.content, 'echo "hello"');
      expect(deserialized.timestamp.toIso8601String(), now.toIso8601String());
      expect(deserialized.isPinned, true);
      expect(deserialized.category, 'Code');
    });

    test('CommandTemplate serialization and deserialization', () {
      final template = CommandTemplate(
        id: 'abc',
        name: 'SSH',
        template: 'ssh {user}@{host}',
        description: 'SSH connect',
      );

      final jsonMap = template.toJson();
      expect(jsonMap['id'], 'abc');
      expect(jsonMap['name'], 'SSH');
      expect(jsonMap['template'], 'ssh {user}@{host}');

      final deserialized = CommandTemplate.fromJson(jsonMap);
      expect(deserialized.id, 'abc');
      expect(deserialized.name, 'SSH');
      expect(deserialized.template, 'ssh {user}@{host}');
      expect(deserialized.description, 'SSH connect');
    });

    test('SyncPeer serialization and deserialization', () {
      final peer = SyncPeer(
        ip: '192.168.1.50',
        port: 41234,
        name: 'My Tablet',
      );

      final jsonMap = peer.toJson();
      expect(jsonMap['ip'], '192.168.1.50');
      expect(jsonMap['port'], 41234);
      expect(jsonMap['name'], 'My Tablet');

      final deserialized = SyncPeer.fromJson(jsonMap);
      expect(deserialized.ip, '192.168.1.50');
      expect(deserialized.port, 41234);
      expect(deserialized.name, 'My Tablet');
    });
  });

  group('Storage Engine Tests', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('cmdclip_test_dir');
      AppStorage.instance.setCustomDirectory(tempDir);
      await AppStorage.instance.init();
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('Initializes with default templates and categories', () {
      final templates = AppStorage.instance.getTemplates();
      expect(templates, isNotEmpty);
      expect(templates.any((t) => t.name.contains('SSH')), true);

      final categories = AppStorage.instance.getCategories();
      expect(categories, contains('Work'));
      expect(categories, contains('Terminal'));
    });

    test('Add, toggle pin, set category, and delete ClipboardItem', () async {
      final item = await AppStorage.instance.addClipboardItem('git commit -m "feat"');
      expect(AppStorage.instance.getHistory().any((i) => i.content == 'git commit -m "feat"'), true);

      // Pin
      await AppStorage.instance.togglePin(item.id);
      expect(AppStorage.instance.getHistory().firstWhere((i) => i.id == item.id).isPinned, true);

      // Category
      await AppStorage.instance.setItemCategory(item.id, 'Code');
      expect(AppStorage.instance.getHistory().firstWhere((i) => i.id == item.id).category, 'Code');

      // Delete
      await AppStorage.instance.deleteClipboardItem(item.id);
      expect(AppStorage.instance.getHistory().any((i) => i.id == item.id), false);
    });

    test('Add and delete custom categories', () async {
      await AppStorage.instance.addCategory('Docker');
      expect(AppStorage.instance.getCategories(), contains('Docker'));

      await AppStorage.instance.deleteCategory('Docker');
      expect(AppStorage.instance.getCategories().contains('Docker'), false);
    });

    test('JSON Export and Import', () async {
      await AppStorage.instance.clearHistory();
      await AppStorage.instance.addClipboardItem('cmd 1');
      await AppStorage.instance.addClipboardItem('cmd 2');

      final jsonText = AppStorage.instance.exportToJson();
      expect(jsonText, contains('cmd 1'));
      expect(jsonText, contains('cmd 2'));

      // Clear & Import
      await AppStorage.instance.clearHistory();
      final count = await AppStorage.instance.importFromJson(jsonText);
      expect(count, 2);
      expect(AppStorage.instance.getHistory().length, 2);
    });

    test('CSV Export and Import with complex content', () async {
      await AppStorage.instance.clearHistory();
      // Add complex multiline item with quotes
      await AppStorage.instance.addClipboardItem('line1\nline2\nwith "quotes"');

      final csvText = AppStorage.instance.exportToCsv();
      expect(csvText, contains('line1'));
      expect(csvText, contains('""quotes""')); // Escaped quotes

      // Clear & Import
      await AppStorage.instance.clearHistory();
      final count = await AppStorage.instance.importFromCsv(csvText);
      expect(count, 1);
      expect(AppStorage.instance.getHistory().first.content, 'line1\nline2\nwith "quotes"');
    });
  });

  group('Secret Mode Unit Tests', () {
    test('Toggle secret mode state', () {
      final mgr = SecretManager.instance;
      mgr.setSecretMode(false);
      expect(mgr.isSecretModeActive, false);

      mgr.toggleSecretMode();
      expect(mgr.isSecretModeActive, true);

      mgr.setSecretMode(false);
    });

    test('copySecretText starts countdown timer', () async {
      final mgr = SecretManager.instance;

      // Call copySecretText with 2 seconds timeout
      await mgr.copySecretText('super-secret-password', 2);
      expect(mgr.secondsRemaining, 2);

      // Wait 3 seconds to ensure timer fires and overwrites system clipboard
      await Future.delayed(const Duration(seconds: 3));
      expect(mgr.secondsRemaining, 0);
    });
  });

  group('Command Template Engine Unit Tests', () {
    test('Parse templates with and without defaults', () {
      final template = 'ssh {user}@{host} -p {port=22}';
      final vars = SecretManager.instance.parseTemplate(template);

      expect(vars.length, 3);
      expect(vars[0].name, 'user');
      expect(vars[0].defaultValue, null);

      expect(vars[2].name, 'port');
      expect(vars[2].defaultValue, '22');
    });

    test('Resolve templates successfully', () {
      final template = 'ssh {user}@{host} -p {port=22}';
      final resolved = SecretManager.instance.resolveTemplate(template, {
        'user': 'alice',
        'host': '192.168.1.10',
      });

      expect(resolved, 'ssh alice@192.168.1.10 -p 22');
    });
  });

  group('Sync Service Network Info', () {
    test('Get local IP helper returns string', () async {
      final ip = await SyncService.instance.getLocalIp();
      expect(ip, isNotEmpty);
      // Valid IP check
      expect(ip.split('.').length, 4);
    });
  });
}
