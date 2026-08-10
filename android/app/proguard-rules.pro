# Keep Firebase Auth persistence (SharedPreferences / token storage).
-keep class com.google.firebase.auth.** { *; }
-keep class com.google.android.gms.internal.firebase-auth-api.** { *; }
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**
