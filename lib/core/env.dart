/// Build-time configuration.
///
/// Everything here comes from `--dart-define`, with defaults that point at the
/// reference deployment. Onboarding a second shop is a build flag, not a source
/// edit:
///
///   flutter build apk \
///     --dart-define=APPWRITE_PROJECT_ID=schnittwerk \
///     --dart-define=SHOP_NAME='Schnittwerk' \
///     --dart-define=STRIPE_PUBLISHABLE_KEY=pk_live_...
///
/// The staff panel is the same binary with `--dart-define=APP_MODE=staff`.
library;

class Env {
  const Env._();

  // ─── which app ─────────────────────────────────────────────────────────────

  static const String _appMode =
      String.fromEnvironment('APP_MODE', defaultValue: 'customer');

  /// `customer` → the booking app the shop puts behind a QR code.
  /// `staff`    → the panel the shop runs its day from.
  static AppMode get appMode =>
      _appMode == 'staff' ? AppMode.staff : AppMode.customer;

  // ─── backend ───────────────────────────────────────────────────────────────

  /// The self-hosted Appwrite. Not Appwrite Cloud: the database, the functions
  /// and every customer's phone number live on our own server, which is what
  /// lets Anlage 2 name one processor instead of two.
  static const String appwriteEndpoint = String.fromEnvironment(
    'APPWRITE_ENDPOINT',
    defaultValue: 'https://write.haey.eu/v1',
  );

  static const String appwriteProjectId =
      String.fromEnvironment('APPWRITE_PROJECT_ID', defaultValue: 'babassam');

  static const String databaseId =
      String.fromEnvironment('APPWRITE_DATABASE_ID', defaultValue: 'barber_db');

  /// Trust a self-signed certificate.
  ///
  /// This used to be on unconditionally, which disabled TLS validation in
  /// release builds — every booking, name and phone number travelling to a
  /// server nobody had verified. It is now opt-in, and [assertSafe] refuses to
  /// let a release build ship with it enabled.
  static const bool allowSelfSignedCerts =
      bool.fromEnvironment('ALLOW_SELF_SIGNED', defaultValue: false);

  /// Appwrite Function ids.
  static const String bookingFunctionId = String.fromEnvironment(
      'BOOKING_FUNCTION_ID',
      defaultValue: 'booking-api');
  static const String stripeFunctionId = String.fromEnvironment(
      'STRIPE_FUNCTION_ID',
      defaultValue: 'stripe-deposit');

  /// Team whose members may use the staff panel. Must match the team the
  /// staff-only table permissions were granted to.
  static const String staffTeamId =
      String.fromEnvironment('STAFF_TEAM_ID', defaultValue: 'staff');

  // ─── shop identity ─────────────────────────────────────────────────────────

  static const String shopName =
      String.fromEnvironment('SHOP_NAME', defaultValue: "BaBa'Ssam");
  static const String shopTagline =
      String.fromEnvironment('SHOP_TAGLINE', defaultValue: 'Der Friseursalon');

  /// The shop's own timezone. Slot arithmetic happens on the server in this
  /// zone; the client uses it only to render times consistently.
  static const String shopTimezone =
      String.fromEnvironment('SHOP_TIMEZONE', defaultValue: 'Europe/Berlin');

  // ─── brand colours ─────────────────────────────────────────────────────────
  //
  // Hex, as `RRGGBB`, `#RRGGBB` or `AARRGGBB`. Empty means "use the house
  // default", so a build that sets none of them is byte-for-byte the
  // BaBa'Ssam brand it always was.
  //
  // A demo build for a prospect normally sets [brandPrimary] and
  // [brandSecondary] and nothing else: `brand.dart` derives the surfaces and
  // the whole dark variant from those two. The remaining defines are escape
  // hatches for a shop that arrives with a real style guide.

  static const String brandPrimary =
      String.fromEnvironment('SHOP_PRIMARY', defaultValue: '');
  static const String brandSecondary =
      String.fromEnvironment('SHOP_SECONDARY', defaultValue: '');
  static const String brandSurface =
      String.fromEnvironment('SHOP_SURFACE', defaultValue: '');
  static const String brandBackground =
      String.fromEnvironment('SHOP_BACKGROUND', defaultValue: '');
  static const String brandOnSurface =
      String.fromEnvironment('SHOP_ON_SURFACE', defaultValue: '');

  static const String brandPrimaryDark =
      String.fromEnvironment('SHOP_PRIMARY_DARK', defaultValue: '');
  static const String brandSecondaryDark =
      String.fromEnvironment('SHOP_SECONDARY_DARK', defaultValue: '');
  static const String brandSurfaceDark =
      String.fromEnvironment('SHOP_SURFACE_DARK', defaultValue: '');
  static const String brandBackgroundDark =
      String.fromEnvironment('SHOP_BACKGROUND_DARK', defaultValue: '');
  static const String brandOnSurfaceDark =
      String.fromEnvironment('SHOP_ON_SURFACE_DARK', defaultValue: '');

  // ─── payments ──────────────────────────────────────────────────────────────

  /// Stripe publishable key. Safe in the client — it can only create
  /// PaymentMethods, never move money. The secret key lives in the Appwrite
  /// Function's variables and nowhere else.
  ///
  /// Empty by default on purpose: shipping a baked-in test key means a build
  /// that silently takes no real money. [assertSafe] catches that too.
  static const String stripePublishableKey =
      String.fromEnvironment('STRIPE_PUBLISHABLE_KEY', defaultValue: '');

  /// Apple Pay merchant identifier, e.g. "merchant.eu.haey.babassam".
  /// Leave empty to disable Apple Pay.
  static const String stripeMerchantIdentifier =
      String.fromEnvironment('STRIPE_MERCHANT_ID', defaultValue: '');

  static bool get paymentsEnabled => stripePublishableKey.isNotEmpty;

  // ─── guard rails ───────────────────────────────────────────────────────────

  /// Fail loudly at boot on a configuration that is fine in debug and
  /// dangerous in release. Called from `main()` before anything else.
  ///
  /// A misconfigured release build should not start; discovering it from a
  /// customer is worse than discovering it from a crash on your own device.
  static void assertSafe() {
    const releaseMode = bool.fromEnvironment('dart.vm.product');
    if (!releaseMode) return;

    final problems = <String>[
      if (allowSelfSignedCerts)
        'ALLOW_SELF_SIGNED is on: TLS certificates would not be validated.',
      if (stripePublishableKey.startsWith('pk_test_'))
        'STRIPE_PUBLISHABLE_KEY is a test key: no real payment would be taken.',
      if (appwriteEndpoint.startsWith('http://'))
        'APPWRITE_ENDPOINT is plain HTTP: traffic would not be encrypted.',
    ];

    if (problems.isNotEmpty) {
      throw StateError(
        'Unsafe release configuration:\n  - ${problems.join('\n  - ')}\n'
        'Fix the --dart-define values for this build.',
      );
    }
  }
}

enum AppMode { customer, staff }
