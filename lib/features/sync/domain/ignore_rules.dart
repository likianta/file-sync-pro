/// A small gitignore-like matcher.
///
/// Supported syntax:
/// - `name` matches a file or directory name at any depth.
/// - `dir/` matches a directory and everything below it.
/// - `/path` anchors the pattern to the sync root.
/// - `*` and `?` match within one path segment; `**` crosses segments.
/// - `!pattern` negates a previous match (last matching rule wins).
///
/// This is intentionally a subset of gitignore. It covers the rules we need
/// without pulling in a third-party dependency.
library;

final class IgnoreRules {
  IgnoreRules._(this._rules);

  factory IgnoreRules.fromPatterns(Iterable<String> patterns) {
    final rules = <_IgnoreRule>[];
    for (final raw in patterns) {
      final rule = _IgnoreRule.tryParse(raw);
      if (rule != null) rules.add(rule);
    }
    return IgnoreRules._(rules);
  }

  factory IgnoreRules.defaults({Iterable<String> extra = const []}) {
    return IgnoreRules.fromPatterns([...defaultPatterns, ...extra]);
  }

  static const defaultPatterns = <String>[
    '.git/',
    '.idea/',
    '.vscode/',
    '__pycache__/',
    '.filesync/',
    '.DS_Store',
    '.gitkeep',
    '~*',
    '*~',
  ];

  final List<_IgnoreRule> _rules;

  bool ignores(String relPath, {required bool isDirectory}) {
    final path = _normalize(relPath);
    if (path.isEmpty) return false;

    var ignored = false;
    for (final rule in _rules) {
      if (rule.matches(path, isDirectory: isDirectory)) {
        ignored = !rule.negated;
      }
    }
    return ignored;
  }

  static String _normalize(String path) {
    var out = path.replaceAll('\\', '/');
    while (out.startsWith('./')) {
      out = out.substring(2);
    }
    while (out.startsWith('/')) {
      out = out.substring(1);
    }
    while (out.endsWith('/')) {
      out = out.substring(0, out.length - 1);
    }
    return out;
  }
}

final class _IgnoreRule {
  _IgnoreRule(this._regex, {required this.negated, required this.dirOnly});

  static _IgnoreRule? tryParse(String raw) {
    var pattern = raw.trim();
    if (pattern.isEmpty || pattern.startsWith('#')) return null;

    var negated = false;
    if (pattern.startsWith('!')) {
      negated = true;
      pattern = pattern.substring(1);
    }

    var dirOnly = false;
    if (pattern.endsWith('/')) {
      dirOnly = true;
      pattern = pattern.substring(0, pattern.length - 1);
    }
    if (pattern.isEmpty) return null;

    var anchored = pattern.startsWith('/');
    if (anchored) pattern = pattern.substring(1);
    if (pattern.isEmpty) return null;

    final hasSlash = pattern.contains('/');
    final prefix = anchored || hasSlash ? '^' : r'^(?:.*/)?';
    final body = _globToRegex(pattern);
    return _IgnoreRule(
      RegExp('$prefix$body\$'),
      negated: negated,
      dirOnly: dirOnly,
    );
  }

  final RegExp _regex;
  final bool negated;
  final bool dirOnly;

  bool matches(String path, {required bool isDirectory}) {
    if (!dirOnly) return _regex.hasMatch(path);

    // A directory-only rule also applies to everything inside that directory.
    final segments = path.split('/');
    final limit = isDirectory ? segments.length : segments.length - 1;
    for (var i = 1; i <= limit; i++) {
      if (_regex.hasMatch(segments.take(i).join('/'))) return true;
    }
    return false;
  }

  static String _globToRegex(String pattern) {
    final out = StringBuffer();
    for (var i = 0; i < pattern.length; i++) {
      final char = pattern[i];
      if (char == '*') {
        if (i + 1 < pattern.length && pattern[i + 1] == '*') {
          i++;
          if (i + 1 < pattern.length && pattern[i + 1] == '/') {
            i++;
            out.write(r'(?:.*/)?');
          } else {
            out.write('.*');
          }
        } else {
          out.write(r'[^/]*');
        }
      } else if (char == '?') {
        out.write(r'[^/]');
      } else {
        out.write(RegExp.escape(char));
      }
    }
    return out.toString();
  }
}
