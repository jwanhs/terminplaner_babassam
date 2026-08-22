import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/brand.dart';
import '../widgets/booking_bar.dart';
import '../widgets/brand_header.dart';
import '../widgets/customer_form.dart';
import '../widgets/date_strip.dart';
import '../widgets/section_header.dart';
import '../widgets/service_picker.dart';
import '../widgets/time_slot_grid.dart';

/// The booking page. Single scroll, everything in view from the first frame.
/// No wizard, no gated steps — the user sees the whole flow and edits any
/// part at any time.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    // The controller is constructed in bootCustomerApp, which owns the API
    // client and the token store it needs.
    final brand = brandOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconBrightness = isDark ? Brightness.light : Brightness.dark;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: brand.surface,
        statusBarIconBrightness: iconBrightness,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: brand.surface,
        systemNavigationBarIconBrightness: iconBrightness,
      ),
      child: Scaffold(
        backgroundColor: brand.background,
        body: Column(
          children: [
            BrandHeader(brand: brand),
            Expanded(
              child: MediaQuery.removePadding(
                context: context,
                removeTop: true,
                child: ListView(
                  padding: const EdgeInsets.only(bottom: S.lg),
                  children: const [
                    SectionHeader('Leistung'),
                    ServicePicker(),
                    SectionHeader('Datum'),
                    DateStrip(),
                    SectionHeader('Uhrzeit'),
                    TimeSlotGrid(),
                    SectionHeader('Deine Daten'),
                    CustomerForm(),
                    SizedBox(height: S.xxxl),
                  ],
                ),
              ),
            ),
          ],
        ),
        bottomNavigationBar: const BookingBar(),
      ),
    );
  }
}
