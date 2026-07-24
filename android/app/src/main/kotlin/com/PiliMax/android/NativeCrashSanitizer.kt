package com.PiliMax.android

internal object NativeCrashSanitizer {
    private const val REDACTED = "[REDACTED]"

    private val queryValue = Regex(
        "(?i)\\b(SESSDATA|bili_jct|csrf|csrf_token|tmp_token|token|" +
            "device_token|access_key|accessKey|access_token|accessToken|" +
            "auth_token|authToken|session_token|sessionToken|refresh_token|" +
            "refreshToken|qrcode_key|captcha_key|verify_key|verify_code|" +
            "sms_code|recaptcha_token|api_key|apiKey|private_key|privateKey|" +
            "secret_key|secretKey|client_secret|clientSecret|id_token|" +
            "idToken|jwt|code|password|passwd|pwd)=([^&\\s;,]+)",
    )
    private val structuredValue = Regex(
        "(?i)([\\\"']?(?:SESSDATA|bili_jct|csrf|csrf_token|tmp_token|" +
            "token|device_token|access_key|accessKey|access_token|" +
            "accessToken|auth_token|authToken|session_token|sessionToken|" +
            "refresh_token|refreshToken|qrcode_key|captcha_key|verify_key|" +
            "verify_code|sms_code|recaptcha_token|api_key|apiKey|" +
            "private_key|privateKey|secret_key|secretKey|client_secret|" +
            "clientSecret|id_token|idToken|jwt|password|passwd|pwd|" +
            "authorization|proxy-authorization|cookie|x-api-key|x-auth-token)[\\\"']?\\s*:\\s*)" +
            "(?:\\\"[^\\\"]*\\\"|'[^']*'|[^,}\\]\\r\\n]+)",
    )
    private val headerValue = Regex(
        "(?i)\\b(authorization|proxy-authorization|cookie|set-cookie|" +
            "x-api-key|x-auth-token)\\s*[:=]\\s*([^\\r\\n]+)",
    )
    private val windowsUserHome = Regex("[A-Za-z]:\\\\Users\\\\[^\\\\\\s]+")
    private val unixUserHome = Regex("/(?:home|Users)/[^/\\s]+")
    private val androidStoragePath = Regex(
        "(?i)/(?:data/(?:user/\\d+/|data/)|storage/emulated/\\d+|" +
            "sdcard|mnt/user/\\d+)/[^\\s;,)\\]}]+",
    )
    private val contentUri = Regex("(?i)\\bcontent://[^\\s]+")
    private val fileUri = Regex("(?i)\\bfile://[^\\s]+")

    fun sanitize(value: String): String {
        return value
            .replace(queryValue) { match -> "${match.groupValues[1]}=$REDACTED" }
            .replace(structuredValue) { match -> "${match.groupValues[1]}$REDACTED" }
            .replace(headerValue) { match -> "${match.groupValues[1]}: $REDACTED" }
            .replace(windowsUserHome, "[user-home]")
            .replace(unixUserHome, "[user-home]")
            .replace(androidStoragePath, "[app-path]")
            .replace(contentUri, "[content-uri]")
            .replace(fileUri, "[file-uri]")
    }
}
