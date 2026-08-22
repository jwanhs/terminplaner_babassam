import 'package:appwrite/appwrite.dart';
import 'package:get/get.dart';

import '../../core/env.dart';

/// Wraps the Appwrite Flutter SDK as a [GetxService] so it survives the app
/// lifecycle and is reachable from any controller via `Get.find()`.
///
/// CRITICAL: no API key. The client SDK authenticates the *user*, not the
/// project. Anything needing an API key — provisioning, admin work, and now
/// every read and write of appointment data — belongs in an Appwrite Function
/// or in tooling like `infra/setup_barber_db.sh`.
///
/// Note there is no `TablesDB` here any more. The customer app has no database
/// access at all: it holds only [functions], through which it calls
/// `booking-api`. That is the whole point of the lockdown — a client that
/// cannot reach the table cannot leak it.
class AppwriteService extends GetxService {
  late final Client client;
  late final Functions functions;

  Future<AppwriteService> init() async {
    client = Client()
      ..setEndpoint(Env.appwriteEndpoint)
      ..setProject(Env.appwriteProjectId);

    // Opt-in, and only ever for a self-hosted server behind a self-signed
    // certificate. This used to be unconditional, which meant release builds
    // sent customers' names and phone numbers over a connection nobody had
    // verified. `Env.assertSafe()` refuses to boot a release build with it on.
    if (Env.allowSelfSignedCerts) {
      client.setSelfSigned(status: true);
    }

    functions = Functions(client);
    return this;
  }
}
