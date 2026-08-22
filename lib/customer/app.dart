import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:get/get.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../core/brand.dart';
import '../core/env.dart';
import '../core/theme.dart';
import 'controllers/booking_controller.dart';
import 'core/appwrite_client.dart';
import 'data/booking_api.dart';
import 'data/token_store.dart';
import 'pages/home_page.dart';

bool get _stripeSupported =>
    kIsWeb ||
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS;

/// Bootstraps the customer-facing booking app — the one behind the QR code on
/// the shop wall. Anonymous by design: no account, no login, and (now) no
/// database access either.
Future<void> bootCustomerApp() async {
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
  ]);

  await initializeDateFormatting('de_DE');

  // Stripe must be initialised before any PaymentSheet call. The publishable
  // key is safe in the client — the secret key only exists in the Appwrite
  // Function's variables. Skipped entirely when unconfigured, so a build
  // without a key simply offers no online payment rather than failing at the
  // sheet.
  if (_stripeSupported && Env.paymentsEnabled) {
    Stripe.publishableKey = Env.stripePublishableKey;
    if (Env.stripeMerchantIdentifier.isNotEmpty) {
      Stripe.merchantIdentifier = Env.stripeMerchantIdentifier;
    }
    await Stripe.instance.applySettings();
  }

  final aw =
      await Get.putAsync<AppwriteService>(() => AppwriteService().init());

  final tokens = await TokenStore.open();
  // Drop manage tokens for long-past bookings; they are sent on every lookup.
  await tokens.prune();
  Get.put<TokenStore>(tokens, permanent: true);

  final api = BookingApi(aw.functions);
  Get.put<BookingApi>(api, permanent: true);

  Get.put<BookingController>(
    BookingController(api: api, tokens: tokens),
    permanent: true,
  );

  runApp(const CustomerApp());
}

class CustomerApp extends StatelessWidget {
  const CustomerApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme(brandLight);
    return GetMaterialApp(
      title: Env.shopName,
      debugShowCheckedModeBanner: false,
      theme: theme.light,
      darkTheme: theme.dark,
      themeMode: ThemeMode.system,
      home: const HomePage(),
      locale: const Locale('de'),
      supportedLocales: const [Locale('de'), Locale('en'), Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          child: child,
        );
      },
    );
  }
}
