class GenerationOptions {
  final int numberOfKeywords;
  final bool shortTitle;
  final bool englishLettersOnly;
  final bool oneWordKeywordsOnly;
  final bool keywordsPhrasesPreferred;
  final String? contextAndInstructions;

  GenerationOptions({
    this.numberOfKeywords = 49,
    this.shortTitle = false,
    this.englishLettersOnly = false,
    this.oneWordKeywordsOnly = false,
    this.keywordsPhrasesPreferred = false,
    this.contextAndInstructions,
  });

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'numberOfKeywords': numberOfKeywords,
      'shortTitle': shortTitle,
      'englishLettersOnly': englishLettersOnly,
      'oneWordKeywordsOnly': oneWordKeywordsOnly,
      'keywordsPhrasesPreferred': keywordsPhrasesPreferred,
    };
    if (contextAndInstructions != null && contextAndInstructions!.isNotEmpty) {
      map['contextAndInstructions'] = contextAndInstructions;
    }
    return map;
  }
}
