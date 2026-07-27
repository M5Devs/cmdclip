import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'models.dart';
import 'storage.dart';
import 'sync_service.dart';
import 'secret_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize persistent storage
  await AppStorage.instance.init();

  // Start polling system clipboard
  SyncService.instance.startClipboardPolling();

  // Start LAN Sync HTTP Server & UDP Broadcast
  await SyncService.instance.startServer();

  runApp(const CmdClipApp());
}

class CmdClipApp extends StatefulWidget {
  const CmdClipApp({super.key});

  @override
  State<CmdClipApp> createState() => _CmdClipAppState();
}

class _CmdClipAppState extends State<CmdClipApp> {
  ThemeMode _themeMode = ThemeMode.dark;

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  void _loadTheme() {
    final mode = AppStorage.instance.themeMode;
    setState(() {
      _themeMode = mode == 'light'
          ? ThemeMode.light
          : mode == 'dark'
              ? ThemeMode.dark
              : ThemeMode.system;
    });
  }

  void refreshTheme() {
    _loadTheme();
  }

  @override
  Widget build(BuildContext context) {
    return ThemeProvider(
      state: this,
      child: MaterialApp(
        title: 'cmdclip',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.teal,
            brightness: Brightness.light,
          ),
          appBarTheme: const AppBarTheme(
            centerTitle: true,
            backgroundColor: Colors.teal,
            foregroundColor: Colors.white,
          ),
        ),
        darkTheme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.teal,
            brightness: Brightness.dark,
          ),
          appBarTheme: AppBarTheme(
            centerTitle: true,
            backgroundColor: Colors.teal.shade900,
            foregroundColor: Colors.white,
          ),
        ),
        themeMode: _themeMode,
        home: const MainLayoutScreen(),
      ),
    );
  }
}

class ThemeProvider extends InheritedWidget {
  final _CmdClipAppState state;

  const ThemeProvider({
    super.key,
    required this.state,
    required super.child,
  });

  static _CmdClipAppState of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<ThemeProvider>()!.state;
  }

  @override
  bool updateShouldNotify(ThemeProvider oldWidget) => true;
}

class MainLayoutScreen extends StatefulWidget {
  const MainLayoutScreen({super.key});

  @override
  State<MainLayoutScreen> createState() => _MainLayoutScreenState();
}

class _MainLayoutScreenState extends State<MainLayoutScreen> {
  int _selectedIndex = 0;
  late StreamSubscription _syncSubscription;

  final List<Widget> _pages = [
    const HistoryPage(),
    const TemplatesPage(),
    const SyncPage(),
    const SettingsPage(),
  ];

  @override
  void initState() {
    super.initState();
    _syncSubscription = SyncService.instance.onSynced.listen((clip) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Synced item copied: ${clip.length > 30 ? "${clip.substring(0, 27)}..." : clip}',
            ),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
        setState(() {}); // refresh the layout if needed
      }
    });
  }

  @override
  void dispose() {
    _syncSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isLargeScreen = width > 750;

    return Scaffold(
      body: Row(
        children: [
          if (isLargeScreen) ...[
            NavigationRail(
              selectedIndex: _selectedIndex,
              onDestinationSelected: (index) {
                setState(() {
                  _selectedIndex = index;
                });
              },
              extended: width > 950,
              labelType: width > 950 ? NavigationRailLabelType.none : NavigationRailLabelType.all,
              leading: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 8.0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.paste_rounded, color: Colors.teal, size: 32),
                    if (width > 950) ...[
                      const SizedBox(width: 12),
                      const Text(
                        'cmdclip',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.teal,
                        ),
                      ),
                    ]
                  ],
                ),
              ),
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.history_rounded),
                  label: Text('History'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.code_rounded),
                  label: Text('Templates'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.sync_alt_rounded),
                  label: Text('LAN Sync'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.settings_rounded),
                  label: Text('Settings'),
                ),
              ],
            ),
            const VerticalDivider(thickness: 1, width: 1),
          ],
          Expanded(
            child: _pages[_selectedIndex],
          ),
        ],
      ),
      bottomNavigationBar: !isLargeScreen
          ? NavigationBar(
              selectedIndex: _selectedIndex,
              onDestinationSelected: (index) {
                setState(() {
                  _selectedIndex = index;
                });
              },
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.history_rounded),
                  label: 'History',
                ),
                NavigationDestination(
                  icon: Icon(Icons.code_rounded),
                  label: 'Templates',
                ),
                NavigationDestination(
                  icon: Icon(Icons.sync_alt_rounded),
                  label: 'LAN Sync',
                ),
                NavigationDestination(
                  icon: Icon(Icons.settings_rounded),
                  label: 'Settings',
                ),
              ],
            )
          : null,
    );
  }
}

// ─── 1. History Page ─────────────────────────────────────────────────────────

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _addController = TextEditingController();
  bool _useRegex = false;
  String _selectedCategory = '';
  int _secondsRemaining = 0;
  StreamSubscription<int>? _countdownSubscription;

  @override
  void initState() {
    super.initState();
    _countdownSubscription = SecretManager.instance.onCountdown.listen((seconds) {
      if (mounted) {
        setState(() {
          _secondsRemaining = seconds;
        });
      }
    });
  }

  @override
  void dispose() {
    _countdownSubscription?.cancel();
    _searchController.dispose();
    _addController.dispose();
    super.dispose();
  }

  List<ClipboardItem> _filterItems(List<ClipboardItem> items) {
    String query = _searchController.text;
    List<ClipboardItem> filtered = items;

    // Filter by Category
    if (_selectedCategory.isNotEmpty) {
      filtered = filtered.where((item) => item.category == _selectedCategory).toList();
    }

    // Filter by Query
    if (query.isEmpty) return filtered;

    if (_useRegex) {
      try {
        final regex = RegExp(query, caseSensitive: false);
        return filtered.where((item) => regex.hasMatch(item.content)).toList();
      } catch (_) {
        // Fallback or show error if regex is invalid
        return [];
      }
    } else {
      final lowerQuery = query.toLowerCase();
      return filtered.where((item) => item.content.toLowerCase().contains(lowerQuery)).toList();
    }
  }

  void _manualAdd() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add Clipboard Entry'),
          content: TextField(
            controller: _addController,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: 'Enter text or command here...',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final text = _addController.text.trim();
                if (text.isNotEmpty) {
                  await AppStorage.instance.addClipboardItem(text);
                  _addController.clear();
                  if (context.mounted) Navigator.pop(context);
                  setState(() {});
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  void _showImportExportMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.download_rounded),
                title: const Text('Export to JSON'),
                onTap: () {
                  Navigator.pop(context);
                  final jsonText = AppStorage.instance.exportToJson();
                  _showTextExportDialog(context, 'JSON Export', jsonText);
                },
              ),
              ListTile(
                leading: const Icon(Icons.download_rounded),
                title: const Text('Export to CSV'),
                onTap: () {
                  Navigator.pop(context);
                  final csvText = AppStorage.instance.exportToCsv();
                  _showTextExportDialog(context, 'CSV Export', csvText);
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.upload_rounded),
                title: const Text('Import from JSON'),
                onTap: () {
                  Navigator.pop(context);
                  _showImportDialog(context, isJson: true);
                },
              ),
              ListTile(
                leading: const Icon(Icons.upload_rounded),
                title: const Text('Import from CSV'),
                onTap: () {
                  Navigator.pop(context);
                  _showImportDialog(context, isJson: false);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showTextExportDialog(BuildContext context, String title, String text) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 500,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Below is your exported data. You can copy it directly to save offline:',
                  style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: TextField(
                    controller: TextEditingController(text: text),
                    readOnly: true,
                    maxLines: 15,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
            ElevatedButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: text));
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Copied export data to clipboard!')),
                  );
                }
              },
              child: const Text('Copy All'),
            ),
          ],
        );
      },
    );
  }

  void _showImportDialog(BuildContext context, {required bool isJson}) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(isJson ? 'Import JSON Data' : 'Import CSV Data'),
          content: SizedBox(
            width: 500,
            child: TextField(
              controller: controller,
              maxLines: 12,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
              decoration: InputDecoration(
                hintText: isJson
                    ? 'Paste your export JSON here...'
                    : 'Paste your export CSV here...\nHeader row must be: "id","timestamp","isPinned","category","content"',
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final content = controller.text.trim();
                if (content.isEmpty) return;
                try {
                  int count = 0;
                  if (isJson) {
                    count = await AppStorage.instance.importFromJson(content);
                  } else {
                    count = await AppStorage.instance.importFromCsv(content);
                  }
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Successfully imported $count new items!')),
                    );
                    setState(() {});
                  }
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error importing: ${e.toString()}')),
                  );
                }
              },
              child: const Text('Import'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSecretMode = SecretManager.instance.isSecretModeActive;
    final rawHistory = AppStorage.instance.getHistory();
    final filteredHistory = _filterItems(rawHistory);
    final categories = AppStorage.instance.getCategories();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Clipboard History'),
        actions: [
          IconButton(
            tooltip: 'Secret Mode',
            icon: Icon(
              isSecretMode ? Icons.security_rounded : Icons.security_outlined,
              color: isSecretMode ? Colors.orange : Colors.white,
            ),
            onPressed: () {
              setState(() {
                SecretManager.instance.toggleSecretMode();
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(SecretManager.instance.isSecretModeActive
                      ? 'Secret Mode activated! Newly copied text won\'t be saved.'
                      : 'Secret Mode deactivated. Copying will now record history.'),
                  backgroundColor: SecretManager.instance.isSecretModeActive ? Colors.deepOrange : Colors.teal,
                ),
              );
            },
          ),
          IconButton(
            tooltip: 'Import/Export',
            icon: const Icon(Icons.swap_vert_rounded),
            onPressed: () => _showImportExportMenu(context),
          ),
          IconButton(
            tooltip: 'Clear All History',
            icon: const Icon(Icons.delete_sweep_rounded),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Clear Clipboard History?'),
                  content: const Text('Are you sure you want to permanently delete all clipboard entries? This cannot be undone.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                      onPressed: () async {
                        await AppStorage.instance.clearHistory();
                        if (context.mounted) Navigator.pop(context);
                        setState(() {});
                      },
                      child: const Text('Clear All', style: TextStyle(color: Colors.white)),
                    )
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Secret Mode Timer Bar
          if (_secondsRemaining > 0)
            Container(
              color: Colors.orange.shade900,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.timer, color: Colors.white),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Secret clip on clipboard! Auto-clearing in $_secondsRemaining seconds...',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      SecretManager.instance.cancelClearTimer();
                    },
                    child: const Text('Cancel Timer', style: TextStyle(color: Colors.white, decoration: TextDecoration.underline)),
                  )
                ],
              ),
            ),

          // Search Bar + Filter Options
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) => setState(() {}),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: _useRegex ? 'Search with regular expression...' : 'Search clipboard history...',
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {});
                              },
                            )
                          : null,
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: 'Regex Search Toggle',
                  icon: Icon(
                    Icons.abc_rounded,
                    color: _useRegex ? Colors.teal : null,
                    size: 28,
                  ),
                  onPressed: () {
                    setState(() {
                      _useRegex = !_useRegex;
                    });
                  },
                ),
              ],
            ),
          ),

          // Category Quick Filtering Chips
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                ChoiceChip(
                  label: const Text('All'),
                  selected: _selectedCategory.isEmpty,
                  onSelected: (selected) {
                    if (selected) setState(() => _selectedCategory = '');
                  },
                ),
                const SizedBox(width: 8),
                ...categories.map((cat) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: ChoiceChip(
                      label: Text(cat),
                      selected: _selectedCategory == cat,
                      onSelected: (selected) {
                        setState(() {
                          _selectedCategory = selected ? cat : '';
                        });
                      },
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Clipboard items List
          Expanded(
            child: filteredHistory.isEmpty
                ? Center(
                    child: Text(
                      _searchController.text.isNotEmpty
                          ? 'No matches found.'
                          : 'Clipboard history is empty.',
                      style: const TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    itemCount: filteredHistory.length,
                    itemBuilder: (context, index) {
                      final item = filteredHistory[index];
                      return ClipboardCard(
                        item: item,
                        onTap: () async {
                          // Copy to system clipboard
                          SyncService.instance.updateLastCopiedText(item.content);
                          await Clipboard.setData(ClipboardData(text: item.content));
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Copied to clipboard!'),
                                duration: Duration(milliseconds: 800),
                              ),
                            );
                          }
                          // Sync on copy
                          if (AppStorage.instance.autoSync) {
                            SyncService.instance.syncToPeers(item.content);
                          }
                        },
                        onTogglePin: () async {
                          await AppStorage.instance.togglePin(item.id);
                          setState(() {});
                        },
                        onDelete: () async {
                          await AppStorage.instance.deleteClipboardItem(item.id);
                          setState(() {});
                        },
                        onAssignCategory: (cat) async {
                          await AppStorage.instance.setItemCategory(item.id, cat);
                          setState(() {});
                        },
                        categories: categories,
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _manualAdd,
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        tooltip: 'Add Clipboard Entry',
        child: const Icon(Icons.add_rounded),
      ),
    );
  }
}

class ClipboardCard extends StatelessWidget {
  final ClipboardItem item;
  final VoidCallback onTap;
  final VoidCallback onTogglePin;
  final VoidCallback onDelete;
  final ValueChanged<String> onAssignCategory;
  final List<String> categories;

  const ClipboardCard({
    super.key,
    required this.item,
    required this.onTap,
    required this.onTogglePin,
    required this.onDelete,
    required this.onAssignCategory,
    required this.categories,
  });

  @override
  Widget build(BuildContext context) {
    // Relative or short formatted timestamp
    final timeStr = '${item.timestamp.hour.toString().padLeft(2, '0')}:${item.timestamp.minute.toString().padLeft(2, '0')} '
        '(${item.timestamp.month}/${item.timestamp.day})';

    return Card(
      elevation: item.isPinned ? 3 : 1,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: item.isPinned
            ? const BorderSide(color: Colors.teal, width: 1.5)
            : BorderSide(color: Colors.grey.withAlpha(50)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      if (item.isPinned) ...[
                        const Icon(Icons.push_pin, size: 16, color: Colors.teal),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        timeStr,
                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      if (item.category.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.teal.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            item.category,
                            style: const TextStyle(fontSize: 10, color: Colors.teal, fontWeight: FontWeight.bold),
                          ),
                        ),
                      const SizedBox(width: 8),
                      // Actions Menu Button
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert, size: 18),
                        padding: EdgeInsets.zero,
                        onSelected: (val) {
                          if (val == 'delete') {
                            onDelete();
                          } else if (val == 'pin') {
                            onTogglePin();
                          } else if (val.startsWith('cat_')) {
                            final cat = val.substring(4);
                            onAssignCategory(cat);
                          }
                        },
                        itemBuilder: (context) {
                          return [
                            PopupMenuItem(
                              value: 'pin',
                              child: Row(
                                children: [
                                  Icon(item.isPinned ? Icons.pin_drop_outlined : Icons.push_pin, size: 16),
                                  const SizedBox(width: 8),
                                  Text(item.isPinned ? 'Unpin' : 'Pin'),
                                ],
                              ),
                            ),
                            const PopupMenuDivider(),
                            ...categories.map((cat) {
                              return PopupMenuItem(
                                value: 'cat_$cat',
                                child: Text('Assign: $cat'),
                              );
                            }),
                            if (item.category.isNotEmpty)
                              const PopupMenuItem(
                                value: 'cat_',
                                child: Text('Remove Category'),
                              ),
                            const PopupMenuDivider(),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(Icons.delete, color: Colors.red, size: 16),
                                  const SizedBox(width: 8),
                                  Text('Delete', style: TextStyle(color: Colors.red)),
                                ],
                              ),
                            ),
                          ];
                        },
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                item.content,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, fontFamily: 'monospace'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── 2. Command Templates Page ────────────────────────────────────────────────

class TemplatesPage extends StatefulWidget {
  const TemplatesPage({super.key});

  @override
  State<TemplatesPage> createState() => _TemplatesPageState();
}

class _TemplatesPageState extends State<TemplatesPage> {
  final _nameController = TextEditingController();
  final _templateController = TextEditingController();
  final _descController = TextEditingController();

  void _addTemplate() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('New Command Template'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Template Name'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _templateController,
                  decoration: const InputDecoration(
                    labelText: 'Template String',
                    hintText: 'e.g. ssh {user}@{host} -p {port=22}',
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _descController,
                  decoration: const InputDecoration(labelText: 'Description'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                final name = _nameController.text.trim();
                final t = _templateController.text.trim();
                final d = _descController.text.trim();
                if (name.isNotEmpty && t.isNotEmpty) {
                  await AppStorage.instance.addTemplate(name, t, d);
                  _nameController.clear();
                  _templateController.clear();
                  _descController.clear();
                  if (context.mounted) Navigator.pop(context);
                  setState(() {});
                }
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }

  void _runTemplate(CommandTemplate t) {
    final vars = SecretManager.instance.parseTemplate(t.template);
    if (vars.isEmpty) {
      // Direct copy
      Clipboard.setData(ClipboardData(text: t.template));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Copied command template directly!')),
      );
      return;
    }

    // Interactive form dialog to resolve placeholders
    final Map<String, TextEditingController> textControllers = {};
    for (final v in vars) {
      textControllers[v.name] = TextEditingController(text: v.defaultValue ?? '');
    }

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Configure: ${t.name}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Fill in variables to construct the shell command:',
                  style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                ),
                const SizedBox(height: 12),
                ...vars.map((v) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: TextField(
                      controller: textControllers[v.name],
                      decoration: InputDecoration(
                        labelText: v.name,
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                final Map<String, String> resolvedValues = {};
                textControllers.forEach((key, controller) {
                  resolvedValues[key] = controller.text.trim();
                });

                final finalCommand = SecretManager.instance.resolveTemplate(t.template, resolvedValues);

                // Copy final command to system clipboard
                SyncService.instance.updateLastCopiedText(finalCommand);
                await Clipboard.setData(ClipboardData(text: finalCommand));

                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Resolved command copied to clipboard: $finalCommand'),
                      duration: const Duration(seconds: 4),
                      action: SnackBarAction(
                        label: 'Save History',
                        onPressed: () async {
                          await AppStorage.instance.addClipboardItem(finalCommand, category: 'Template');
                          setState(() {});
                        },
                      ),
                    ),
                  );
                }
              },
              child: const Text('Generate & Copy'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final templates = AppStorage.instance.getTemplates();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Command Templates'),
      ),
      body: templates.isEmpty
          ? const Center(
              child: Text(
                'No templates saved yet.',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: templates.length,
              itemBuilder: (context, index) {
                final t = templates[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    title: Text(t.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        if (t.description.isNotEmpty) ...[
                          Text(t.description, style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic)),
                          const SizedBox(height: 6),
                        ],
                        Container(
                          padding: const EdgeInsets.all(6),
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            t.template,
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Fill Variables',
                          icon: const Icon(Icons.play_arrow_rounded, color: Colors.teal, size: 28),
                          onPressed: () => _runTemplate(t),
                        ),
                        IconButton(
                          tooltip: 'Delete Template',
                          icon: const Icon(Icons.delete, color: Colors.redAccent, size: 20),
                          onPressed: () async {
                            await AppStorage.instance.deleteTemplate(t.id);
                            setState(() {});
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addTemplate,
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        tooltip: 'Add Template',
        child: const Icon(Icons.add_rounded),
      ),
    );
  }
}

// ─── 3. LAN Sync Page ────────────────────────────────────────────────────────

class SyncPage extends StatefulWidget {
  const SyncPage({super.key});

  @override
  State<SyncPage> createState() => _SyncPageState();
}

class _SyncPageState extends State<SyncPage> {
  final _ipController = TextEditingController();
  final _portController = TextEditingController(text: '41234');
  String _localIp = 'Loading...';
  bool _isAutoSync = true;

  @override
  void initState() {
    super.initState();
    _loadNetworkInfo();
    _isAutoSync = AppStorage.instance.autoSync;
  }

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    super.dispose();
  }

  void _loadNetworkInfo() async {
    final ip = await SyncService.instance.getLocalIp();
    if (mounted) {
      setState(() {
        _localIp = ip;
      });
    }
  }

  void _pairDevice() async {
    final ip = _ipController.text.trim();
    final portStr = _portController.text.trim();

    if (ip.isEmpty || portStr.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter valid Peer IP and Port.')),
      );
      return;
    }

    final port = int.tryParse(portStr);
    if (port == null) return;

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      await SyncService.instance.pairPeerManually(ip, port);

      if (mounted) {
        Navigator.pop(context); // close loader
        _ipController.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Paired successfully!')),
        );
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // close loader
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pair: ${e.toString()}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final serverRunning = SyncService.instance.isServerRunning;
    final peers = AppStorage.instance.getPeers();

    return Scaffold(
      appBar: AppBar(
        title: const Text('LAN Clipboard Sync'),
        actions: [
          IconButton(
            tooltip: 'Refresh Network Info',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _loadNetworkInfo();
              SyncService.instance.broadcastPresence();
            },
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status Card
            Card(
              color: serverRunning ? Colors.teal.withOpacity(0.12) : Colors.red.withOpacity(0.12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(
                          serverRunning ? Icons.check_circle_rounded : Icons.error_rounded,
                          color: serverRunning ? Colors.teal : Colors.red,
                          size: 32,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                serverRunning ? 'LAN Sync Active' : 'LAN Sync Inactive',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                              ),
                              Text(
                                serverRunning
                                    ? 'Listening for clipboards on local network...'
                                    : 'Port binding failed or server stopped.',
                                style: const TextStyle(fontSize: 13, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: serverRunning,
                          onChanged: (active) async {
                            if (active) {
                              await SyncService.instance.startServer();
                            } else {
                              await SyncService.instance.stopServer();
                            }
                            setState(() {});
                          },
                        )
                      ],
                    ),
                    const Divider(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Column(
                          children: [
                            const Text('Local IP Address', style: TextStyle(fontSize: 12, color: Colors.grey)),
                            const SizedBox(height: 4),
                            Text(_localIp, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          ],
                        ),
                        Column(
                          children: [
                            const Text('Sync Port', style: TextStyle(fontSize: 12, color: Colors.grey)),
                            const SizedBox(height: 4),
                            Text('${SyncService.instance.serverPort}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          ],
                        ),
                      ],
                    )
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Sync Preference Switches
            SwitchListTile(
              title: const Text('Auto-Sync New Copies'),
              subtitle: const Text('Immediately pushes newly copied items to all paired devices'),
              value: _isAutoSync,
              onChanged: (val) async {
                setState(() {
                  _isAutoSync = val;
                });
                await AppStorage.instance.updateSetting('autoSync', val);
              },
            ),
            const Divider(),

            // Add Peer Manually Form
            const Text('Pair New Device Manually', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _ipController,
                    decoration: const InputDecoration(
                      labelText: 'Device IP',
                      hintText: 'e.g. 192.168.1.15',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _portController,
                    decoration: const InputDecoration(
                      labelText: 'Port',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(60, 55),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: _pairDevice,
                  child: const Text('Pair'),
                )
              ],
            ),
            const SizedBox(height: 24),

            // Paired Devices List
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Active Paired Devices', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                TextButton(
                  onPressed: () {
                    SyncService.instance.broadcastPresence();
                    setState(() {});
                  },
                  child: const Text('UDP Discovery'),
                )
              ],
            ),
            const SizedBox(height: 8),
            peers.isEmpty
                ? const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Center(
                        child: Text(
                          'No paired devices. Devices running cmdclip on the same LAN will auto-discover, or you can pair manually above.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey, fontSize: 13),
                        ),
                      ),
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: peers.length,
                    itemBuilder: (context, index) {
                      final p = peers[index];
                      return Card(
                        child: ListTile(
                          leading: const Icon(Icons.devices_rounded, color: Colors.teal),
                          title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('${p.ip}:${p.port}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.redAccent),
                                onPressed: () async {
                                  await AppStorage.instance.removePeer(p.ip, p.port);
                                  setState(() {});
                                },
                              )
                            ],
                          ),
                        ),
                      );
                    },
                  )
          ],
        ),
      ),
    );
  }
}

// ─── 4. Settings Page ────────────────────────────────────────────────────────

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _deviceController = TextEditingController();
  final _categoryInputController = TextEditingController();
  int _secretTimeout = 30;

  @override
  void initState() {
    super.initState();
    _deviceController.text = AppStorage.instance.deviceName;
    _secretTimeout = AppStorage.instance.secretTimeoutSeconds;
  }

  @override
  void dispose() {
    _deviceController.dispose();
    _categoryInputController.dispose();
    super.dispose();
  }

  void _addCategory() async {
    final cat = _categoryInputController.text.trim();
    if (cat.isNotEmpty) {
      await AppStorage.instance.addCategory(cat);
      _categoryInputController.clear();
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = ThemeProvider.of(context);
    final categories = AppStorage.instance.getCategories();
    final isDark = AppStorage.instance.themeMode == 'dark';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Theme settings
            const Text('Appearance', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            SwitchListTile(
              title: const Text('Dark Mode Theme'),
              subtitle: const Text('Switch between teal light and dark modes'),
              value: isDark,
              onChanged: (active) async {
                final mode = active ? 'dark' : 'light';
                await AppStorage.instance.updateSetting('themeMode', mode);
                themeProvider.refreshTheme();
                setState(() {});
              },
            ),
            const Divider(),

            // Device Name Settings
            const Text('Device Configuration', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            TextField(
              controller: _deviceController,
              decoration: const InputDecoration(
                labelText: 'Local Device Name',
                border: OutlineInputBorder(),
                helperText: 'This name identifies this device when syncing across LAN.',
              ),
              onChanged: (name) async {
                if (name.trim().isNotEmpty) {
                  await AppStorage.instance.updateSetting('deviceName', name.trim());
                }
              },
            ),
            const SizedBox(height: 16),

            // Secret Mode Configuration
            const Text('Secret Mode Configuration', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            ListTile(
              title: const Text('Clipboard Auto-Delete Timeout'),
              subtitle: Text('Clears copied secrets after: $_secretTimeout seconds'),
              trailing: SizedBox(
                width: 150,
                child: Slider(
                  min: 5,
                  max: 120,
                  divisions: 23,
                  label: '$_secretTimeout s',
                  value: _secretTimeout.toDouble(),
                  onChanged: (val) async {
                    setState(() {
                      _secretTimeout = val.round();
                    });
                    await AppStorage.instance.updateSetting('secretTimeoutSeconds', _secretTimeout);
                  },
                ),
              ),
            ),
            const Divider(),

            // Manage categories
            const Text('User Categories', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _categoryInputController,
                    decoration: const InputDecoration(
                      labelText: 'New Category Name',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _addCategory,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(80, 50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Add'),
                )
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: categories.map((cat) {
                return Chip(
                  label: Text(cat),
                  onDeleted: () async {
                    await AppStorage.instance.deleteCategory(cat);
                    setState(() {});
                  },
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}
