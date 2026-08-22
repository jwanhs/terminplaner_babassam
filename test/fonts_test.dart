import 'dart:io';

import 'package:babassam/core/theme.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards the fix for the runtime font fetch.
///
/// Both failure modes here are silent, which is why they are worth a test.
/// Re-adding `google_fonts` would quietly restore a request to Google on every
/// page load; and a font family named in `theme.dart` that `pubspec.yaml` does
/// not declare does not throw — Flutter just renders the platform font, which
/// looks like a design regression rather than a missing asset.
void main() {
  final pubspec = File('pubspec.yaml').readAsStringSync();

  group('fonts are bundled, not fetched', () {
    test('google_fonts is not a dependency', () {
      final declared = RegExp(r'^\s{2}google_fonts\s*:', multiLine: true);

      expect(
        pubspec.contains(declared),
        isFalse,
        reason: 'google_fonts downloads its font files from Google at runtime, '
            'which sends every visitor\'s IP address to Google before they '
            'have booked anything. Bundle the family under assets/fonts '
            'instead — see the note in pubspec.yaml.',
      );
    });

    test('pubspec declares the families theme.dart asks for', () {
      expect(pubspec, contains('family: $displayFamily'));
      expect(pubspec, contains('family: $bodyFamily'));
    });

    test('every weight the widgets use is declared and present', () {
      // The app asks for w400, w500, w600 and w700. Flutter falls back to the
      // nearest declared weight rather than synthesising one, so a missing
      // file renders subtly wrong instead of failing.
      const expected = [
        'assets/fonts/Inter-Regular.ttf',
        'assets/fonts/Inter-Medium.ttf',
        'assets/fonts/Inter-SemiBold.ttf',
        'assets/fonts/Inter-Bold.ttf',
        'assets/fonts/PlayfairDisplay-Medium.ttf',
        'assets/fonts/PlayfairDisplay-SemiBold.ttf',
        'assets/fonts/PlayfairDisplay-Bold.ttf',
      ];

      for (final path in expected) {
        expect(pubspec, contains(path), reason: '$path is not declared');
        expect(File(path).existsSync(), isTrue, reason: '$path is missing');
      }
    });

    test('the OFL licence texts ship with the fonts', () {
      // Both families are SIL Open Font License 1.1, which requires the licence
      // to travel with the files when they are redistributed — and every build
      // we hand a shop redistributes them.
      expect(File('assets/fonts/OFL-Inter.txt').existsSync(), isTrue);
      expect(
        File('assets/fonts/OFL-PlayfairDisplay.txt').existsSync(),
        isTrue,
      );
    });

    test('the bundled files are real TrueType fonts', () {
      // Google's CSS endpoint serves EOT, WOFF or TTF depending on the user
      // agent that asked. Only TTF is any use to Flutter, and the wrong one
      // downloads happily and fails at render time.
      final fonts = Directory('assets/fonts')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.ttf'));

      expect(fonts, isNotEmpty);
      for (final font in fonts) {
        final magic = font.readAsBytesSync().take(4).toList();
        expect(
          magic,
          [0x00, 0x01, 0x00, 0x00],
          reason: '${font.path} is not a TrueType font',
        );
      }
    });
  });
}
