import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../core/brand.dart';
import '../controllers/booking_controller.dart';

class CustomerForm extends StatelessWidget {
  const CustomerForm({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.find<BookingController>();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: S.lg),
      child: Column(
        children: [
          TextField(
            controller: c.nameCtl,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Dein Name',
              prefixIcon: Icon(Icons.person_outline),
              hintText: 'Wie dürfen wir dich ansprechen?',
            ),
          ),
          const SizedBox(height: S.md),
          TextField(
            controller: c.phoneCtl,
            keyboardType: TextInputType.phone,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[\d\+\s\-\(\)]')),
            ],
            decoration: const InputDecoration(
              labelText: 'Telefon',
              prefixIcon: Icon(Icons.phone_outlined),
              hintText: 'Damit wir dich bei Änderungen erreichen',
            ),
          ),
        ],
      ),
    );
  }
}
