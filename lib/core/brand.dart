import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'env.dart';

/// Brand identity for BaBa'Ssam.
///
/// Built around three pillars:
///   • Oxblood — the chair, the leather strop, old-world authority.
///   • Antique gold — the brass barber pole fittings, the polish.
///   • Warm cream — clean towels, old marble, calm.
///
/// For a second shop, none of this is edited: [brandLight] and [brandDark]
/// layer the `SHOP_*` dart-defines over these house values, so onboarding a
/// brand is a build flag. The rest of the app reads [brandOf].
class BrandIdentity {
  const BrandIdentity({
    required this.businessName,
    required this.tagline,
    required this.primary,
    required this.secondary,
    required this.surface,
    required this.background,
    required this.onSurface,
  });

  final String businessName;
  final String tagline;

  /// Anchor colour — used for CTAs, header band, selected states.
  final Color primary;

  /// Accent — used sparingly for highlights, prices, hairline rules.
  final Color secondary;

  /// Card / form surfaces.
  final Color surface;

  /// App background.
  final Color background;

  final Color onSurface;
}

/// The BaBa'Ssam house brand.
const babassam = BrandIdentity(
  businessName: "BaBa'Ssam",
  tagline: 'Der Friseursalon',
  primary: Color(0xFF6E1A1F), // oxblood
  secondary: Color(0xFFC9A961), // antique gold
  surface: Color(0xFFFBF6EB), // ivory
  background: Color(0xFFF4ECDC), // warm cream
  onSurface: Color(0xFF2A1810), // dark espresso
);

/// Dark counterpart. Same oxblood/gold/cream relationships but lit from a low
/// spotlight — warm-black room, polished brass, the sign turned on.
const babassamDark = BrandIdentity(
  businessName: "BaBa'Ssam",
  tagline: 'Der Friseursalon',
  primary: Color(0xFFCC4350), // sign-lit crimson — legible on warm-dark
  secondary: Color(0xFFC9A961), // antique gold — unchanged
  surface: Color(0xFF241612), // warm espresso for cards / headers
  background: Color(0xFF160B0A), // deeper warm-black scaffold
  onSurface: Color(0xFFF4ECDC), // warm cream type
);

// ─── Per-shop resolution ───────────────────────────────────────────────────────

/// True when this build carries a brand of its own, rather than the house one.
///
/// Setting either anchor colour switches the surfaces from the BaBa'Ssam
/// cream-and-oxblood palette to ones derived from the shop's own hues. Without
/// it, a shop that set only its primary would get a red-tinted background with
/// a blue logo on it.
final bool _custom = _isSet(Env.brandPrimary) || _isSet(Env.brandSecondary);

bool _isSet(String define) => define.trim().isNotEmpty;

/// The brand this build paints with in light mode.
///
/// Top-level finals are initialised lazily and exactly once, and every input is
/// a compile-time define, so the parsing and the HSL arithmetic below happen on
/// first paint and never again.
final BrandIdentity brandLight = _resolveLight();

/// The dark counterpart. Derived from [brandLight] unless the `*_DARK` defines
/// say otherwise — a demo build should need one colour, not ten.
final BrandIdentity brandDark = _resolveDark(brandLight);

/// Returns the brand variant that matches the current [Brightness]. Use this
/// anywhere a widget paints with brand tokens so the dark theme stays cohesive.
BrandIdentity brandOf(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark ? brandDark : brandLight;

/// Explicit define, else the derived colour for a custom brand, else the house.
Color _pick(String define, Color derived, Color house) =>
    parseBrandHex(define) ?? (_custom ? derived : house);

BrandIdentity _resolveLight() {
  const house = babassam;
  final primary = parseBrandHex(Env.brandPrimary) ?? house.primary;
  final secondary = parseBrandHex(Env.brandSecondary) ?? house.secondary;

  // Paper takes the *secondary* hue: an accent is where a shop's warmth lives,
  // and tinting a whole background with a saturated primary reads as a colour
  // cast rather than as a brand.
  final paper = HSLColor.fromColor(secondary).hue;
  final ink = HSLColor.fromColor(primary).hue;

  final surface = _tint(paper, 0.55, 0.965);
  final background = _tint(paper, 0.45, 0.925);
  final onSurface = _tint(ink, 0.30, 0.115);

  return BrandIdentity(
    businessName: Env.shopName,
    tagline: Env.shopTagline,
    primary: primary,
    secondary: secondary,
    surface: _pick(Env.brandSurface, surface, house.surface),
    background: _pick(Env.brandBackground, background, house.background),
    onSurface: _pick(Env.brandOnSurface, onSurface, house.onSurface),
  );
}

BrandIdentity _resolveDark(BrandIdentity light) {
  const house = babassamDark;

  // Oxblood on cream is authority; oxblood on near-black is a smudge. The dark
  // primary is the same hue lit from a low spotlight — lifted to a legible
  // lightness and held back from neon.
  final primary = relight(light.primary, 0.53, 0.62);
  final secondary = relight(light.secondary, 0.59, 0.55);

  final paper = HSLColor.fromColor(light.primary).hue;
  final ink = HSLColor.fromColor(light.secondary).hue;

  final surface = _tint(paper, 0.22, 0.105);
  final background = _tint(paper, 0.24, 0.065);
  final onSurface = _tint(ink, 0.32, 0.915);

  return BrandIdentity(
    businessName: light.businessName,
    tagline: light.tagline,
    primary: _pick(Env.brandPrimaryDark, primary, house.primary),
    secondary: _pick(Env.brandSecondaryDark, secondary, house.secondary),
    surface: _pick(Env.brandSurfaceDark, surface, house.surface),
    background: _pick(Env.brandBackgroundDark, background, house.background),
    onSurface: _pick(Env.brandOnSurfaceDark, onSurface, house.onSurface),
  );
}

/// Parses `RRGGBB`, `#RRGGBB`, `0xAARRGGBB` or `AARRGGBB` into a [Color].
///
/// Returns null on anything else — including the empty string, which is the
/// normal "not set" case. A typo in a build flag falls back to the house colour
/// rather than throwing: a shop discovering a bad hex should see the wrong
/// shade of red, not a customer-facing crash at the till.
@visibleForTesting
Color? parseBrandHex(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return null;
  if (s.startsWith('#')) s = s.substring(1);
  if (s.startsWith('0x') || s.startsWith('0X')) s = s.substring(2);
  if (s.length == 6) s = 'FF$s';
  if (s.length != 8) return null;
  final value = int.tryParse(s, radix: 16);
  return value == null ? null : Color(value);
}

/// A fully opaque colour at [hue] degrees, with [saturation] and [lightness]
/// in 0..1.
Color _tint(double hue, double saturation, double lightness) =>
    HSLColor.fromAHSL(1, hue, saturation, lightness).toColor();

/// The same hue at a new [lightness], with saturation capped at
/// [maxSaturation] so a shop that picks a vivid brand colour does not get a
/// fluorescent dark theme.
@visibleForTesting
Color relight(Color c, double lightness, double maxSaturation) {
  final hsl = HSLColor.fromColor(c);
  final saturation = math.min(hsl.saturation, maxSaturation);
  return HSLColor.fromAHSL(1, hsl.hue, saturation, lightness).toColor();
}

// ─── Configuration ─────────────────────────────────────────────────────────────
//
// Endpoint, project, keys and shop identity all live in [Env] and arrive by
// `--dart-define`, so a second shop is a build flag rather than a source edit.
// This file is brand *appearance* only.
//
// What used to be here and is gone on purpose:
//
//   * `AppwriteConfig` table names. The customer app no longer reads or writes
//     any table — availability, booking, cancellation and lookup all go
//     through the booking-api Function, because the appointments table is
//     staff-only now. There is nothing left for it to name.
//   * `selfSigned = true`. It disabled TLS validation in every build; it is
//     now `Env.allowSelfSignedCerts`, off by default, and a release build that
//     turns it on refuses to start.
//   * A hardcoded `pk_test_…` Stripe key, which meant a build that forgot its
//     dart-define silently took no real money. `Env.stripePublishableKey` is
//     empty by default and payments are simply offered only when it is set.
//   * `enableRealtime`. Slot freshness is a server round trip now; there is no
//     local grid to keep in sync.

// ─── Spacing scale ─────────────────────────────────────────────────────────────

/// 4-pt spacing scale used across the app. Keep layout rhythm consistent.
class S {
  const S._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;
}
