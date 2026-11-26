# Keep Xsolla SDK entry points if the optional dependency is compiled in.
-keep class com.xsolla.android.** { *; }
-dontwarn com.xsolla.android.**

# Firebase / Firestore model classes are accessed reflectively.
-keep class com.google.firebase.** { *; }
-keepattributes Signature
-keepattributes *Annotation*

# Google Sign-In
-keep class com.google.android.gms.auth.** { *; }

# Flutter
-keep class io.flutter.** { *; }
