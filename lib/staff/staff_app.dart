// `show Client`: the Appwrite SDK also exports a `Locale` service class, which
// otherwise shadows Flutter's `Locale` in the localisation setup below.
import 'package:appwrite/appwrite.dart' show Client;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:get/get.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../core/brand.dart';
import '../core/env.dart';
import '../core/theme.dart';
import 'controllers/agenda_controller.dart';
import 'controllers/staff_auth_controller.dart';
import 'data/staff_repository.dart';
import 'pages/agenda_page.dart';
import 'pages/login_page.dart';

/// Boots the staff panel — the same binary as the customer app, built with
/// `--dart-define=APP_MODE=staff`.
///
/// No Stripe initialisation here: staff never present a payment sheet. Card
/// payments are the customer's flow and land through the Stripe webhook;
/// cash at the counter is a status write.
Future<void> bootStaffApp() async {
  await initializeDateFormatting('de_DE');

  final client = Client()
    ..setEndpoint(Env.appwriteEndpoint)
    ..setProject(Env.appwriteProjectId);
  if (Env.allowSelfSignedCerts) {
    client.setSelfSigned(status: true);
  }

  final repo = StaffRepository(client);
  Get.put<StaffRepository>(repo, permanent: true);
  Get.put<StaffAuthController>(StaffAuthController(repo), permanent: true);

  runApp(const StaffApp());
}

class StaffApp extends StatelessWidget {
  const StaffApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme(brandLight);
    return GetMaterialApp(
      title: '${Env.shopName} · Team',
      debugShowCheckedModeBanner: false,
      theme: theme.light,
      darkTheme: theme.dark,
      themeMode: ThemeMode.system,
      locale: const Locale('de'),
      supportedLocales: const [Locale('de'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const _StaffGate(),
    );
  }
}

/// Routes on session state. The panel is never built for a user who is not in
/// the staff team — and if one somehow got here, every query behind it would
/// come back empty anyway, because the tables grant `team:staff`.
class _StaffGate extends StatelessWidget {
  const _StaffGate();

  @override
  Widget build(BuildContext context) {
    final auth = Get.find<StaffAuthController>();
    return Obx(() {
      switch (auth.state.value) {
        case AuthState.checking:
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        case AuthState.signedOut:
        case AuthState.notStaff:
          return const StaffLoginPage();
        case AuthState.ready:
          // Rebuilt fresh per sign-in so a second user on a shared till does
          // not inherit the previous one's loaded day.
          Get.put<AgendaController>(
            AgendaController(Get.find<StaffRepository>()),
            tag: auth.userEmail.value ?? 'staff',
          );
          return AgendaPage(tag: auth.userEmail.value ?? 'staff');
      }
    });
  }
}
