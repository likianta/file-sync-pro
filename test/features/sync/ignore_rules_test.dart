import 'package:file_sync_pro/features/sync/domain/ignore_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('IgnoreRules', () {
    final rules = IgnoreRules.defaults(
      extra: ['build/', '*.log', '!keep.log', '/root-only.txt', '**/cache/'],
    );

    test('defaults ignore VCS and OS noise', () {
      expect(rules.ignores('.git/config', isDirectory: false), isTrue);
      expect(rules.ignores('.git', isDirectory: true), isTrue);
      expect(rules.ignores('docs/.DS_Store', isDirectory: false), isTrue);
      expect(rules.ignores('docs/.gitkeep', isDirectory: false), isTrue);
      expect(rules.ignores('.filesync/journal/x', isDirectory: false), isTrue);
    });

    test('does not ignore normal files', () {
      expect(rules.ignores('docs/readme.md', isDirectory: false), isFalse);
      expect(rules.ignores('sub', isDirectory: true), isFalse);
    });

    test('directory-only rules cover descendants', () {
      expect(rules.ignores('build', isDirectory: true), isTrue);
      expect(rules.ignores('build/out.txt', isDirectory: false), isTrue);
      expect(rules.ignores('build', isDirectory: false), isFalse);
    });

    test('basename patterns match at any depth', () {
      expect(rules.ignores('a/b.log', isDirectory: false), isTrue);
      expect(rules.ignores('b.log', isDirectory: false), isTrue);
      expect(rules.ignores('docs/readme.log', isDirectory: false), isTrue);
      expect(rules.ignores('docs/readme.md', isDirectory: false), isFalse);
    });

    test('negation wins when it appears later', () {
      expect(rules.ignores('other.log', isDirectory: false), isTrue);
      expect(rules.ignores('keep.log', isDirectory: false), isFalse);
      expect(rules.ignores('sub/keep.log', isDirectory: false), isFalse);
    });

    test('leading slash anchors to the root', () {
      expect(rules.ignores('root-only.txt', isDirectory: false), isTrue);
      expect(rules.ignores('sub/root-only.txt', isDirectory: false), isFalse);
    });

    test('double star matches deep directories', () {
      expect(rules.ignores('a/cache', isDirectory: true), isTrue);
      expect(rules.ignores('a/b/cache', isDirectory: true), isTrue);
      expect(rules.ignores('a/b/cache/x.txt', isDirectory: false), isTrue);
    });

    test('trailing-tilde backup files are ignored', () {
      expect(rules.ignores('note~', isDirectory: false), isTrue);
      expect(rules.ignores('~note', isDirectory: false), isTrue);
      expect(rules.ignores('sub/note~', isDirectory: false), isTrue);
    });

    test('supports anchored directories and glob suffixes', () {
      final gitbook = IgnoreRules.fromPatterns([
        '/.git/',
        '/blog/',
        '/plugins/',
        '/scripts/',
        '/setup/',
        '/source-docs/临时/',
        '/.gitignore',
        '/poetry.lock',
        '/pyproject.toml',
        '**.b64.html',
        '.DS_Store',
      ]);

      expect(gitbook.ignores('.git/config', isDirectory: false), isTrue);
      expect(gitbook.ignores('blog/index.html', isDirectory: false), isTrue);
      expect(gitbook.ignores('plugins/a/b.js', isDirectory: false), isTrue);
      expect(gitbook.ignores('scripts/build.py', isDirectory: false), isTrue);
      expect(
        gitbook.ignores('source-docs/临时/note.md', isDirectory: false),
        isTrue,
      );
      expect(gitbook.ignores('.gitignore', isDirectory: false), isTrue);
      expect(gitbook.ignores('poetry.lock', isDirectory: false), isTrue);
      expect(gitbook.ignores('page.b64.html', isDirectory: false), isTrue);
      expect(gitbook.ignores('a/b/page.b64.html', isDirectory: false), isTrue);
      expect(gitbook.ignores('docs/.DS_Store', isDirectory: false), isTrue);

      expect(
        gitbook.ignores('source-docs/note.md', isDirectory: false),
        isFalse,
      );
      expect(gitbook.ignores('docs/poetry.lock', isDirectory: false), isFalse);
      expect(gitbook.ignores('page.b64.html.bak', isDirectory: false), isFalse);
    });
  });
}
