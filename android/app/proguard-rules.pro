# R8 rules for Haram Blur.
#
# Flutter's engine ships its own consumer rules; the entries below cover the
# native libraries used by the accessibility service and the on-device models,
# which reach their classes through JNI or reflection and would otherwise be
# renamed or stripped.

# --- TensorFlow Lite / LiteRT ------------------------------------------------
-keep class org.tensorflow.lite.** { *; }
-keep class com.google.ai.edge.litert.** { *; }
-dontwarn org.tensorflow.lite.**

# --- ML Kit face detection (used by the awrah/person pass) -------------------
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_face.** { *; }
-dontwarn com.google.mlkit.**
-dontwarn com.google.android.gms.**

# --- Accessibility service, receivers and device admin ----------------------
# They are instantiated by Android from the manifest, so their names must
# survive shrinking.
-keep class com.haramblur.haram_blur.SystemWideBlurService { *; }
-keep class com.haramblur.haram_blur.BootReceiver { *; }
-keep class com.haramblur.haram_blur.DeviceAdmin { *; }
-keep class com.haramblur.haram_blur.MainActivity { *; }

# --- Optional annotations the ML Kit artifacts reference but do not bundle ---
-dontwarn javax.annotation.**
-dontwarn org.checkerframework.**
-dontwarn com.google.errorprone.annotations.**
