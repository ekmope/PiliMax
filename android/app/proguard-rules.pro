-dontwarn javax.annotation.Nullable
-dontwarn org.conscrypt.Conscrypt
-dontwarn org.conscrypt.OpenSSLProvider
-keep class com.PiliMax.android.AndroidHelper { public *; }
-keep class com.PiliMax.android.AndroidHelper$ToDart { public *; }
-keep class com.PiliMax.android.PlaybackExitSnapshot {
    public static void recordForegroundService(android.content.Context, boolean);
    public static void recordForegroundServiceStartFailed(android.content.Context);
}
