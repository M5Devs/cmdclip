class ClipboardItem {
  final String id;
  final String content;
  final DateTime timestamp;
  final bool isPinned;
  final String category;
  final bool isSecret;

  ClipboardItem({
    required this.id,
    required this.content,
    required this.timestamp,
    this.isPinned = false,
    this.category = '',
    this.isSecret = false,
  });

  ClipboardItem copyWith({
    String? id,
    String? content,
    DateTime? timestamp,
    bool? isPinned,
    String? category,
    bool? isSecret,
  }) {
    return ClipboardItem(
      id: id ?? this.id,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      isPinned: isPinned ?? this.isPinned,
      category: category ?? this.category,
      isSecret: isSecret ?? this.isSecret,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'content': content,
      'timestamp': timestamp.toIso8601String(),
      'isPinned': isPinned,
      'category': category,
      'isSecret': isSecret,
    };
  }

  factory ClipboardItem.fromJson(Map<String, dynamic> json) {
    return ClipboardItem(
      id: json['id'] as String,
      content: json['content'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      isPinned: (json['isPinned'] as bool?) ?? false,
      category: (json['category'] as String?) ?? '',
      isSecret: (json['isSecret'] as bool?) ?? false,
    );
  }
}

class CommandTemplate {
  final String id;
  final String name;
  final String template;
  final String description;

  CommandTemplate({
    required this.id,
    required this.name,
    required this.template,
    required this.description,
  });

  CommandTemplate copyWith({
    String? id,
    String? name,
    String? template,
    String? description,
  }) {
    return CommandTemplate(
      id: id ?? this.id,
      name: name ?? this.name,
      template: template ?? this.template,
      description: description ?? this.description,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'template': template,
      'description': description,
    };
  }

  factory CommandTemplate.fromJson(Map<String, dynamic> json) {
    return CommandTemplate(
      id: json['id'] as String,
      name: json['name'] as String,
      template: json['template'] as String,
      description: (json['description'] as String?) ?? '',
    );
  }
}

class SyncPeer {
  final String ip;
  final int port;
  final String name;
  final DateTime? lastSynced;
  final bool isPaired;

  SyncPeer({
    required this.ip,
    required this.port,
    required this.name,
    this.lastSynced,
    this.isPaired = true,
  });

  SyncPeer copyWith({
    String? ip,
    int? port,
    String? name,
    DateTime? lastSynced,
    bool? isPaired,
  }) {
    return SyncPeer(
      ip: ip ?? this.ip,
      port: port ?? this.port,
      name: name ?? this.name,
      lastSynced: lastSynced ?? this.lastSynced,
      isPaired: isPaired ?? this.isPaired,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'ip': ip,
      'port': port,
      'name': name,
      'lastSynced': lastSynced?.toIso8601String(),
      'isPaired': isPaired,
    };
  }

  factory SyncPeer.fromJson(Map<String, dynamic> json) {
    return SyncPeer(
      ip: json['ip'] as String,
      port: json['port'] as int,
      name: json['name'] as String,
      lastSynced: json['lastSynced'] != null
          ? DateTime.parse(json['lastSynced'] as String)
          : null,
      isPaired: (json['isPaired'] as bool?) ?? true,
    );
  }
}
