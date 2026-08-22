import 'package:flutter/material.dart';

import 'core/env.dart';
import 'customer/app.dart' as customer;
import 'staff/staff_app.dart' as staff;

/// One binary, two apps.
///
///   flutter run                              → the customer booking app
///   flutter run --dart-define=APP_MODE=staff → the staff panel
///
/// They share the brand, the theme and the shop's configuration, and nothing
/// else: the customer app is anonymous and talks only to the booking-api
/// Function, while the panel signs in and reads the tables directly. Keeping
/// them in one project keeps the two halves of a booking — what the customer
/// asked for and what the shop sees — from drifting apart.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Refuses to boot a release build configured unsafely — a test Stripe key, a
  // plaintext endpoint, or TLS validation switched off.
  Env.assertSafe();

  switch (Env.appMode) {
    case AppMode.staff:
      await staff.bootStaffApp();
    case AppMode.customer:
      await customer.bootCustomerApp();
  }
}
