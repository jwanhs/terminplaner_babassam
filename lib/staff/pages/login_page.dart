import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/brand.dart';
import '../../core/env.dart';
import '../../core/widgets/app_button.dart';
import '../controllers/staff_auth_controller.dart';

/// Staff sign-in.
///
/// Plain e-mail + password against Appwrite Account. The accounts are created
/// by `infra/setup_staff_team.sh` and put in the `staff` team — which is the
/// team every staff-only table permission names, so being signed in here and
/// being able to read an appointment are the same fact.
class StaffLoginPage extends StatefulWidget {
  const StaffLoginPage({super.key});

  @override
  State<StaffLoginPage> createState() => _StaffLoginPageState();
}

class _StaffLoginPageState extends State<StaffLoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit(StaffAuthController auth) {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    auth.signIn(_email.text, _password.text);
  }

  @override
  Widget build(BuildContext context) {
    final auth = Get.find<StaffAuthController>();
    final t = Theme.of(context);
    final b = brandOf(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(S.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.content_cut, size: 40, color: b.primary),
                    const SizedBox(height: S.lg),
                    Text(
                      Env.shopName,
                      textAlign: TextAlign.center,
                      style: t.textTheme.headlineMedium,
                    ),
                    const SizedBox(height: S.xs),
                    Text(
                      'Team-Anmeldung',
                      textAlign: TextAlign.center,
                      style: t.textTheme.bodyMedium?.copyWith(
                        color: t.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: S.xxl),
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      autofillHints: const [AutofillHints.username],
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'E-Mail',
                        prefixIcon: Icon(Icons.alternate_email),
                      ),
                      validator: (v) => (v == null || !v.contains('@'))
                          ? 'Bitte E-Mail eingeben'
                          : null,
                    ),
                    const SizedBox(height: S.md),
                    TextFormField(
                      controller: _password,
                      obscureText: _obscure,
                      autofillHints: const [AutofillHints.password],
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _submit(auth),
                      decoration: InputDecoration(
                        labelText: 'Passwort',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(_obscure
                              ? Icons.visibility
                              : Icons.visibility_off),
                          onPressed: () => setState(() => _obscure = !_obscure),
                          tooltip: _obscure ? 'Anzeigen' : 'Verbergen',
                        ),
                      ),
                      validator: (v) => (v == null || v.length < 8)
                          ? 'Mindestens 8 Zeichen'
                          : null,
                    ),
                    Obx(() {
                      final err = auth.errorText.value;
                      if (err == null) return const SizedBox(height: S.xl);
                      return Padding(
                        padding: const EdgeInsets.only(top: S.lg, bottom: S.sm),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.error_outline,
                                size: 18, color: t.colorScheme.error),
                            const SizedBox(width: S.sm),
                            Expanded(
                              child: Text(
                                err,
                                style: t.textTheme.bodySmall
                                    ?.copyWith(color: t.colorScheme.error),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    Obx(() => AppButton(
                          label: 'Anmelden',
                          icon: Icons.login,
                          expand: true,
                          loading: auth.busy.value,
                          onPressed: () => _submit(auth),
                        )),
                    const SizedBox(height: S.xl),
                    Text(
                      'Nur für Mitarbeitende. Kundinnen und Kunden buchen '
                      'über die öffentliche App.',
                      textAlign: TextAlign.center,
                      style: t.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
