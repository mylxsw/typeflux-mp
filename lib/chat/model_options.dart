/// Public model metadata returned by the authenticated Ask catalog.
/// No provider names, limits or prices are inferred when metadata is absent.
class ModelOption {
  ModelOption.fromJson(this.json);

  final Map<String, dynamic> json;
  String get id => json['id'] as String? ?? '';
  String get reference => 'cloud:$id';
  String get name => json['name'] as String? ?? id;
  bool get isDefault => id == 'default';
  bool? get vision => json['vision'] as bool?;
  int? get contextWindowTokens =>
      _positiveInteger(json['context_window_tokens']);
  int? get maxOutputTokens => _positiveInteger(json['max_output_tokens']);

  /// Matches the server and macOS compatibility behavior for older catalogs.
  List<String> get reasoningEfforts {
    if ((json['capabilities'] as Map?)?['reasoning'] != true) return const [];
    final declared = json['reasoning_efforts'] as List? ?? const [];
    final offered = reasoningLevels.where(declared.contains).toList();
    return offered.isEmpty ? const ['low', 'medium', 'high'] : offered;
  }

  bool get supportsReasoning => reasoningEfforts.isNotEmpty;
  bool isHighestEffort(String effort) =>
      effort.isNotEmpty && reasoningEfforts.lastOrNull == effort;

  /// Validate public price metadata in the same range as the native client.
  String? get multiplierLabel {
    final value = (json['pricing'] as Map?)?['multiplier'];
    if (value is! String ||
        !RegExp(r'^[0-9]+(?:\.[0-9]{1,4})?$').hasMatch(value)) {
      return null;
    }
    final number = double.tryParse(value);
    if (number == null || number <= 0 || number > 100) return null;
    final normalized = number == number.roundToDouble()
        ? number.toInt().toString()
        : number.toString();
    return '${normalized}X';
  }

  static int? _positiveInteger(dynamic value) =>
      value is int && value > 0 ? value : null;
}

const reasoningLevels = ['low', 'medium', 'high', 'xhigh', 'max'];

/// Empty means automatic. A tie always chooses the lighter supported level.
String nearestReasoningEffort(String value, List<String> offered) {
  if (value.isEmpty || value == 'auto' || offered.isEmpty) return '';
  final origin = reasoningLevels.indexOf(value);
  if (origin < 0) return '';
  String nearest = '';
  var distance = reasoningLevels.length;
  for (final level in reasoningLevels) {
    if (!offered.contains(level)) continue;
    final delta = (reasoningLevels.indexOf(level) - origin).abs();
    if (delta < distance) {
      nearest = level;
      distance = delta;
    }
  }
  return nearest;
}
