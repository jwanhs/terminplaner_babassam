package eu.haey.babassam

import io.flutter.embedding.android.FlutterFragmentActivity

// flutter_stripe requires FlutterFragmentActivity so the Stripe SDK can attach
// its bottom-sheet payment-sheet fragments to the host activity's
// FragmentManager. Stays a no-op subclass otherwise.
class MainActivity : FlutterFragmentActivity()
