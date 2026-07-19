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

  bool get isMacro => type == 'macro';
  String? get macroFile => params['macroFile'] as String?;
  bool get loop => params['loop'] as bool? ?? false;
  bool get smartRecognition => params['smartRecognition'] as bool? ?? false;
}

class Plugin {
  final String id;
  final String name;
  final String version;
  final String description;
  final String author;
  final String? iconPath;
  final bool builtIn;
  final List<PluginAction> actions;
  bool enabled;

  Plugin({
    required this.id,
    required this.name,
    required this.version,
    required this.description,
    required this.author,
    this.iconPath,
    this.builtIn = false,
    this.actions = const [],
    this.enabled = false,
  });

  factory Plugin.fromManifest(
    Map<String, dynamic> json, {
    String? iconPath,
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
      builtIn: builtIn,
      actions: actions,
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
      'builtIn': builtIn,
      'actions': actions
          .map((a) => {
                'type': a.type,
                'label': a.label,
                ...a.params,
              })
          .toList(),
      'enabled': enabled,
    };
  }

  factory Plugin.fromJson(Map<String, dynamic> json) {
    final plugin = Plugin.fromManifest(
      json,
      iconPath: json['iconPath'] as String?,
      builtIn: json['builtIn'] as bool? ?? false,
    );
    plugin.enabled = json['enabled'] as bool? ?? false;
    return plugin;
  }
}
