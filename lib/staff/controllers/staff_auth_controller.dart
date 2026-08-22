import 'package:appwrite/appwrite.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../data/staff_repository.dart';

enum AuthState { checking, signedOut, notStaff, ready }

/// Session state for the staff panel.
///
/// Note what happens on [AuthState.notStaff]: a signed-in user who is not in
/// the staff team is signed straight back out. They could not read a single
/// appointment anyway — the table grants `team:staff` and nothing else — so
/// leaving them on a half-working screen would only make a permissions error
/// look like a bug.
class StaffAuthController extends GetxController {
  StaffAuthController(this._repo);

  final StaffRepository _repo;

  final state = AuthState.checking.obs;
  final busy = false.obs;
  final errorText = RxnString();
  final userName = RxnString();
  final userEmail = RxnString();

  @override
  void onInit() {
    super.onInit();
    restore();
  }

  /// Resume an existing session on boot, if there is one.
  Future<void> restore() async {
    state.value = AuthState.checking;
    try {
      final user = await _repo.currentUser();
      if (user == null) {
        state.value = AuthState.signedOut;
        return;
      }
      if (!await _repo.isStaff()) {
        await _repo.signOut();
        state.value = AuthState.notStaff;
        return;
      }
      userName.value = user.name;
      userEmail.value = user.email;
      state.value = AuthState.ready;
    } catch (e, st) {
      debugPrint('[StaffAuth.restore] $e');
      debugPrintStack(stackTrace: st, label: 'StaffAuth.restore');
      state.value = AuthState.signedOut;
    }
  }

  Future<void> signIn(String email, String password) async {
    if (busy.value) return;
    busy.value = true;
    errorText.value = null;
    try {
      final user = await _repo.signIn(email: email.trim(), password: password);
      if (!await _repo.isStaff()) {
        await _repo.signOut();
        state.value = AuthState.notStaff;
        errorText.value = 'Dieses Konto gehört nicht zum Team.';
        return;
      }
      userName.value = user.name;
      userEmail.value = user.email;
      state.value = AuthState.ready;
    } on AppwriteException catch (e) {
      // Never say which half was wrong: that turns the login into a way of
      // discovering which staff e-mail addresses exist.
      errorText.value = switch (e.type) {
        'user_invalid_credentials' => 'E-Mail oder Passwort stimmt nicht.',
        'general_rate_limit_exceeded' =>
          'Zu viele Versuche. Bitte kurz warten.',
        _ => e.message ?? 'Anmeldung fehlgeschlagen.',
      };
    } catch (e, st) {
      debugPrint('[StaffAuth.signIn] $e');
      debugPrintStack(stackTrace: st, label: 'StaffAuth.signIn');
      errorText.value = 'Anmeldung fehlgeschlagen.';
    } finally {
      busy.value = false;
    }
  }

  Future<void> signOut() async {
    busy.value = true;
    try {
      await _repo.signOut();
    } finally {
      userName.value = null;
      userEmail.value = null;
      errorText.value = null;
      state.value = AuthState.signedOut;
      busy.value = false;
    }
  }
}
