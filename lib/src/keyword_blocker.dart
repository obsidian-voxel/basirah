/// One keyword hit inside a piece of text.
class KeywordMatch {
  /// The configured keyword (as the user sees it), e.g. `xxx*`.
  final String keyword;

  /// The text that actually matched, e.g. `xxxtube`.
  final String evidence;

  /// Offset of the hit in the searched text.
  final int index;

  const KeywordMatch(this.keyword, this.evidence, this.index);

  @override
  String toString() => 'KeywordMatch($keyword → $evidence)';
}

/// Case-insensitive keyword matcher with `*` wildcards.
///
/// This is the tested reference for the filter that runs on every window: the
/// accessibility service runs the same semantics natively (`BlockMatcher.kt`)
/// so blocking keeps working even when the Flutter engine is not running. Keep
/// the two in step; the unit tests in `test/block_rules_test.dart` pin the
/// behaviour.
class KeywordBlocker {
  KeywordBlocker(Iterable<String> keywords, {this.wholeWord = false})
      : _patterns = [
          for (final keyword in normalizeAll(keywords))
            _KeywordPattern(keyword, _compile(keyword, wholeWord)),
        ];

  /// When true, `porn` only matches the standalone word, not `pornography`.
  final bool wholeWord;

  final List<_KeywordPattern> _patterns;

  bool get isEmpty => _patterns.isEmpty;

  int get length => _patterns.length;

  /// First hit in reading order, or null. Each pattern is a wildcard match
  /// (`xxx*` → `xxx` followed by anything).
  KeywordMatch? match(String text) {
    if (text.isEmpty || _patterns.isEmpty) return null;
    final haystack = text.toLowerCase();
    KeywordMatch? best;
    for (final pattern in _patterns) {
      final hit = pattern.regex.firstMatch(haystack);
      if (hit == null) continue;
      if (best == null || hit.start < best.index) {
        best = KeywordMatch(
          pattern.keyword,
          hit.group(0) ?? pattern.keyword,
          hit.start,
        );
      }
    }
    return best;
  }

  /// Convenience wrapper for one-off checks (tests, Settings preview).
  static KeywordMatch? firstMatch(
    Iterable<String> keywords,
    String text, {
    bool wholeWord = false,
  }) =>
      KeywordBlocker(keywords, wholeWord: wholeWord).match(text);

  /// Trims, drops blanks and case-insensitive duplicates, keeps user order.
  static List<String> normalizeAll(Iterable<String> keywords) {
    final seen = <String>{};
    final out = <String>[];
    for (final raw in keywords) {
      final keyword = raw.trim().toLowerCase();
      if (!isValid(keyword)) continue;
      if (!seen.add(keyword)) continue;
      out.add(keyword);
    }
    return out;
  }

  /// A keyword must contain at least one letter or digit and be ≥ 2 chars;
  /// a bare `*` would block everything.
  static bool isValid(String keyword) {
    final trimmed = keyword.trim();
    if (trimmed.length < 2) return false;
    return RegExp(r'[a-z0-9]', caseSensitive: false).hasMatch(trimmed);
  }

  static RegExp _compile(String keyword, bool wholeWord) {
    final escaped = RegExp.escape(keyword).replaceAll(r'\*', '.*');
    final body = wholeWord ? '(?<![a-z0-9])$escaped(?![a-z0-9])' : escaped;
    return RegExp(body, caseSensitive: false);
  }
}

class _KeywordPattern {
  final String keyword;
  final RegExp regex;
  const _KeywordPattern(this.keyword, this.regex);
}
