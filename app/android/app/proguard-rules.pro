# Flutter-specific ProGuard rules

# Keep Flutter engine
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }

# Keep Firebase classes
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }

# Keep Gson (used by Firebase)
-keepattributes Signature
-keepattributes *Annotation*
-dontwarn sun.misc.**
-keep class com.google.gson.** { *; }

# Keep play core (for deferred components)
-keep class com.google.android.play.core.** { *; }
-dontwarn com.google.android.play.core.**

# cloud_firestore gRPC native bridge
-keep class io.grpc.** { *; }
-keep class io.opencensus.** { *; }
-dontwarn io.grpc.**
-dontwarn io.opencensus.**

# flutter_local_notifications
-keep class com.dexterous.** { *; }
-dontwarn com.dexterous.**

# share_plus
-keep class dev.fluttercommunity.plus.share.** { *; }
-dontwarn dev.fluttercommunity.plus.share.**

# permission_handler
-keep class com.baseflow.permissionhandler.** { *; }
-dontwarn com.baseflow.permissionhandler.**

# image_picker / image_picker_android
-keep class io.flutter.plugins.imagepicker.** { *; }
-dontwarn io.flutter.plugins.imagepicker.**

# flutter_image_compress
-keep class com.fluttercandies.flutter_image_compress.** { *; }
-dontwarn com.fluttercandies.flutter_image_compress.**

# printing (pdf generation via Pdfium)
-keep class com.advantus.printing.** { *; }
-dontwarn com.advantus.printing.**
-keep class com.pdfium.** { *; }
-dontwarn com.pdfium.**

# url_launcher / url_launcher_android
-keep class io.flutter.plugins.urllauncher.** { *; }
-dontwarn io.flutter.plugins.urllauncher.**

# path_provider / path_provider_android
-keep class io.flutter.plugins.pathprovider.** { *; }
-dontwarn io.flutter.plugins.pathprovider.**

# fl_chart (pure Dart — no native bridge, but keep its JVM reflection targets)
-dontwarn com.github.mikephil.charting.**

# shimmer (pure Dart widget — no native bridge needed)

# cached_network_image / flutter_cache_manager
-keep class com.baseflow.cachemanager.** { *; }
-dontwarn com.baseflow.cachemanager.**

# shared_preferences / shared_preferences_android
-keep class io.flutter.plugins.sharedpreferences.** { *; }
-dontwarn io.flutter.plugins.sharedpreferences.**

# sqflite (used by flutter_cache_manager internally)
-keep class com.tekartik.sqflite.** { *; }
-dontwarn com.tekartik.sqflite.**

# Keep app model classes for Firestore data binding
-keep class footwear.pk.com.** { *; }