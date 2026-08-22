import 'package:babassam/core/brand.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The brand is now assembled from `SHOP_*` dart-defines so a demo build can
/// carry a prospect's own name and colours. These tests run with none of those
/// defines set, which is the reference deployment's own configuration — so the
/// first group is the regression guard that matters most: onboarding a second
/// shop must not have quietly restyled the first one.
void main() {
  group('a build with no SHOP_* defines is the house brand', () {
    test('light mode matches babassam exactly', () {
      expect(brandLight.businessName, babassam.businessName);
      expect(brandLight.tagline, babassam.tagline);
      expect(brandLight.primary, babassam.primary);
      expect(brandLight.secondary, babassam.secondary);
      expect(brandLight.surface, babassam.surface);
      expect(brandLight.background, babassam.background);
      expect(brandLight.onSurface, babassam.onSurface);
    });

    test('dark mode matches babassamDark exactly', () {
      expect(brandDark.primary, babassamDark.primary);
      expect(brandDark.secondary, babassamDark.secondary);
      expect(brandDark.surface, babassamDark.surface);
      expect(brandDark.background, babassamDark.background);
      expect(brandDark.onSurface, babassamDark.onSurface);
    });
  });

  group('parseBrandHex', () {
    const oxblood = Color(0xFF6E1A1F);

    test('accepts the shapes a build flag is likely to carry', () {
      expect(parseBrandHex('6E1A1F'), oxblood);
      expect(parseBrandHex('#6E1A1F'), oxblood);
      expect(parseBrandHex('FF6E1A1F'), oxblood);
      expect(parseBrandHex('0xFF6E1A1F'), oxblood);
      expect(parseBrandHex('  #6E1A1F  '), oxblood);
    });

    test('is case-insensitive', () {
      expect(parseBrandHex('6e1a1f'), oxblood);
    });

    // A typo in a --dart-define should cost the shop the wrong shade of red,
    // not a crash in front of a customer. Every one of these falls back.
    test('returns null rather than throwing on junk', () {
      expect(parseBrandHex(''), isNull);
      expect(parseBrandHex('   '), isNull);
      expect(parseBrandHex('oxblood'), isNull);
      expect(parseBrandHex('#12345'), isNull);
      expect(parseBrandHex('#1234567'), isNull);
      expect(parseBrandHex('zzzzzz'), isNull);
    });
  });

  group('relight', () {
    test('lifts a dark brand colour to a legible lightness', () {
      const oxblood = Color(0xFF6E1A1F);
      final lit = HSLColor.fromColor(relight(oxblood, 0.53, 0.62));

      expect(lit.lightness, closeTo(0.53, 0.02));
      // Same colour, turned up — not a different one.
      expect(lit.hue, closeTo(HSLColor.fromColor(oxblood).hue, 1.0));
    });

    test('caps saturation so a vivid brand does not go fluorescent', () {
      const vivid = Color(0xFFFF0000); // fully saturated
      final lit = HSLColor.fromColor(relight(vivid, 0.53, 0.62));

      expect(lit.saturation, closeTo(0.62, 0.02));
    });

    test('leaves a muted colour to its own saturation', () {
      const muted = Color(0xFF7A6A62); // saturation well under the cap
      final before = HSLColor.fromColor(muted).saturation;
      final after = HSLColor.fromColor(relight(muted, 0.53, 0.62)).saturation;

      expect(after, closeTo(before, 0.02));
    });
  });
}
