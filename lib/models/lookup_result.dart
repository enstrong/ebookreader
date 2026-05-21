class LookupDefinition {
  final String source;
  final String word;
  final String partOfSpeech;
  final String definition;
  final String example;

  const LookupDefinition({
    required this.source,
    required this.word,
    required this.partOfSpeech,
    required this.definition,
    required this.example,
  });

  factory LookupDefinition.fromJson(Map<String, dynamic> json) {
    return LookupDefinition(
      source: json['source']?.toString() ?? '',
      word: json['word']?.toString() ?? '',
      partOfSpeech: json['partOfSpeech']?.toString() ?? '',
      definition: json['definition']?.toString() ?? '',
      example: json['example']?.toString() ?? '',
    );
  }
}

class LookupTranslation {
  final String source;
  final String text;
  final List<String> alternatives;

  const LookupTranslation({
    required this.source,
    required this.text,
    required this.alternatives,
  });

  factory LookupTranslation.fromJson(Map<String, dynamic> json) {
    final rawAlternatives = json['alternatives'];
    return LookupTranslation(
      source: json['source']?.toString() ?? '',
      text: json['text']?.toString() ?? '',
      alternatives: rawAlternatives is List
          ? rawAlternatives
                .map((item) => item.toString().trim())
                .where((item) => item.isNotEmpty)
                .toList()
          : const [],
    );
  }
}

class LookupResult {
  final String normalizedText;
  final String detectedLanguage;
  final String targetLanguage;
  final List<LookupDefinition> definitions;
  final LookupTranslation? translation;
  final List<String> errors;

  const LookupResult({
    required this.normalizedText,
    required this.detectedLanguage,
    required this.targetLanguage,
    required this.definitions,
    required this.translation,
    required this.errors,
  });

  factory LookupResult.fromJson(Map<String, dynamic> json) {
    final rawDefinitions = json['definitions'];
    final rawErrors = json['errors'];
    final rawTranslation = json['translation'];

    return LookupResult(
      normalizedText: json['normalizedText']?.toString() ?? '',
      detectedLanguage: json['detectedLanguage']?.toString() ?? '',
      targetLanguage: json['targetLanguage']?.toString() ?? '',
      definitions: rawDefinitions is List
          ? rawDefinitions
                .whereType<Map>()
                .map(
                  (item) => LookupDefinition.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .toList()
          : const [],
      translation: rawTranslation is Map
          ? LookupTranslation.fromJson(
              Map<String, dynamic>.from(rawTranslation),
            )
          : null,
      errors: rawErrors is List
          ? rawErrors.map((item) => item.toString()).toList()
          : const [],
    );
  }

  bool get hasUsefulResult =>
      definitions.isNotEmpty || (translation?.text.trim().isNotEmpty ?? false);
}
