class PluginAction {
  final String type;
  final String label;
  final Map<String, dynamic> params;

  PluginAction({
    required this.type,
    required this.label,
    required this.params,
  });

  factory PluginAction.fromJson(Map<String, dynamic> json) {
    final params = Map<String, dynamic>.from(json);
    params.remove('type');
    params.remove('label');
    return PluginAction(
      type: json['type'] as String,
      label: json['label'] as String? ?? '',
      params: params,
    );
  }
}

class Plugin {
  final String id;
  final String name;
  final String version;
  final String description;
  final String author;
  final String? iconPath;
  final String? iconName;
  final bool builtIn;
  final List<PluginAction> actions;
  final String type;
  bool enabled;
  bool pinned;
  DateTime? pinnedAt;

  Plugin({
    required this.id,
    required this.name,
    required this.version,
    required this.description,
    required this.author,
    this.iconPath,
    this.iconName,
    this.builtIn = false,
    this.actions = const [],
    this.enabled = false,
    this.type = 'macro',
    this.pinned = false,
    this.pinnedAt,
  });

  String get pluginType => type;
  bool get isFloater => type == 'floaterPlugin';

  factory Plugin.fromManifest(
    Map<String, dynamic> json, {
    String? iconPath,
    String? iconName,
    bool builtIn = false,
  }) {
    final actions = (json['actions'] as List<dynamic>? ?? [])
        .map((e) => PluginAction.fromJson(e as Map<String, dynamic>))
        .toList();
    return Plugin(
      id: json['id'] as String,
      name: json['name'] as String,
      version: json['version'] as String? ?? '1.0.0',
      description: json['description'] as String? ?? '',
      author: json['author'] as String? ?? '',
      iconPath: iconPath,
      iconName: iconName ?? json['iconName'] as String?,
      builtIn: builtIn,
      actions: actions,
      type: json['type'] as String? ?? 'macro',
      pinned: json['pinned'] as bool? ?? false,
      pinnedAt: json['pinnedAt'] != null
          ? DateTime.tryParse(json['pinnedAt'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'version': version,
      'description': description,
      'author': author,
      'iconPath': iconPath,
      'iconName': iconName,
      'builtIn': builtIn,
      'type': type,
      'actions': actions
          .map((a) => {
                'type': a.type,
                'label': a.label,
                ...a.params,
              })
          .toList(),
      'enabled': enabled,
      'pinned': pinned,
      'pinnedAt': pinnedAt?.toIso8601String(),
    };
  }

  factory Plugin.fromJson(Map<String, dynamic> json) {
    final plugin = Plugin.fromManifest(
      json,
      iconPath: json['iconPath'] as String?,
      iconName: json['iconName'] as String?,
      builtIn: json['builtIn'] as bool? ?? false,
    );
    plugin.enabled = json['enabled'] as bool? ?? false;
    return plugin;
  }

  Plugin copyWith({
    String? id,
    String? name,
    String? version,
    String? description,
    String? author,
    String? iconPath,
    String? iconName,
    bool? builtIn,
    List<PluginAction>? actions,
    bool? enabled,
    String? type,
    bool? pinned,
    DateTime? pinnedAt,
  }) {
    return Plugin(
      id: id ?? this.id,
      name: name ?? this.name,
      version: version ?? this.version,
      description: description ?? this.description,
      author: author ?? this.author,
      iconPath: iconPath ?? this.iconPath,
      iconName: iconName ?? this.iconName,
      builtIn: builtIn ?? this.builtIn,
      actions: actions ?? this.actions,
      enabled: enabled ?? this.enabled,
      type: type ?? this.type,
      pinned: pinned ?? this.pinned,
      pinnedAt: pinnedAt ?? this.pinnedAt,
    );
  }
}
