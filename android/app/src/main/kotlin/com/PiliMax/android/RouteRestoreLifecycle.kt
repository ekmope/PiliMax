package com.PiliMax.android

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import android.os.Process
import android.system.OsConstants
import androidx.annotation.RequiresApi
import kotlin.system.exitProcess

/**
 * Records enough native process lifecycle state to distinguish a reclaimable
 * background-process death from explicit exits and broken launches.
 */
internal object RouteRestoreLifecycle {
    const val CHANNEL_NAME = "com.PiliMax.android/route_restore_lifecycle"

    private const val PREFS_NAME = "pilimax_route_restore_lifecycle"
    private const val SCHEMA_VERSION = 1
    private const val KEY_SCHEMA_VERSION = "schema_version"
    private const val KEY_PROCESS_ID = "process_id"
    private const val KEY_PROCESS_STARTED_AT = "process_started_at"
    private const val KEY_VERSION_CODE = "version_code"
    private const val KEY_LAST_UPDATE_TIME = "last_update_time"
    private const val KEY_VISIBILITY = "visibility"
    private const val KEY_EXPLICIT_LAUNCH = "explicit_launch"
    private const val KEY_INVALIDATED = "invalidated"
    private const val KEY_LAST_EVENT = "last_event"

    private const val VISIBILITY_FOREGROUND = "foreground"
    private const val VISIBILITY_BACKGROUND = "background"

    private val lock = Any()
    private var processInitialized = false
    private var restoreEligibility = false
    private var restoreEligibilityConsumed = false
    private var crashHandlerInstalled = false

    fun onActivityCreated(context: Context, intent: Intent?) {
        val appContext = context.applicationContext
        val version = appVersion(appContext)
        val explicitLaunch = !isLauncherIntent(intent)

        synchronized(lock) {
            if (!processInitialized) {
                val previousSession = readSession(preferences(appContext))
                restoreEligibility =
                    !explicitLaunch &&
                    version != null &&
                    isEligiblePreviousSession(appContext, previousSession, version)
                restoreEligibilityConsumed = false
                processInitialized = true
            }

            preferences(appContext).edit()
                .putInt(KEY_SCHEMA_VERSION, SCHEMA_VERSION)
                .putInt(KEY_PROCESS_ID, Process.myPid())
                .putLong(KEY_PROCESS_STARTED_AT, System.currentTimeMillis())
                .putLong(KEY_VERSION_CODE, version?.versionCode ?: -1L)
                .putLong(KEY_LAST_UPDATE_TIME, version?.lastUpdateTime ?: -1L)
                .putString(KEY_VISIBILITY, VISIBILITY_FOREGROUND)
                .putBoolean(KEY_EXPLICIT_LAUNCH, explicitLaunch)
                .putBoolean(KEY_INVALIDATED, false)
                .putString(KEY_LAST_EVENT, "activity_created")
                .commit()

            installCrashHandler(appContext)
        }
    }

    fun onActivityStarted(context: Context) {
        preferences(context.applicationContext).edit()
            .putString(KEY_VISIBILITY, VISIBILITY_FOREGROUND)
            .putBoolean(KEY_INVALIDATED, false)
            .putString(KEY_LAST_EVENT, "activity_started")
            .commit()
    }

    fun onActivityStopped(context: Context) {
        updateVisibility(context, VISIBILITY_BACKGROUND, "activity_stopped")
    }

    fun onActivityDestroyed(
        context: Context,
        isFinishing: Boolean,
        isChangingConfigurations: Boolean,
    ) {
        if (isFinishing && !isChangingConfigurations) {
            cancelPendingRestore()
            invalidate(context, "activity_finished")
        }
    }

    fun onNewIntent(context: Context, intent: Intent?) {
        val explicitLaunch = !isLauncherIntent(intent)
        if (explicitLaunch) cancelPendingRestore()
        preferences(context.applicationContext).edit()
            .putBoolean(KEY_EXPLICIT_LAUNCH, explicitLaunch)
            .putString(KEY_LAST_EVENT, "new_intent")
            .commit()
    }

    fun consumeRestoreEligibility(): Boolean = synchronized(lock) {
        if (!processInitialized || restoreEligibilityConsumed) {
            return@synchronized false
        }
        restoreEligibilityConsumed = true
        restoreEligibility
    }

    fun markTaskRemoved(context: Context) {
        cancelPendingRestore()
        invalidate(context, "task_removed")
    }

    fun markIntentionalExit(context: Context) {
        cancelPendingRestore()
        invalidate(context, "intentional_exit")
    }

    private fun cancelPendingRestore() {
        synchronized(lock) {
            restoreEligibility = false
        }
    }

    private fun updateVisibility(context: Context, visibility: String, event: String) {
        preferences(context.applicationContext).edit()
            .putString(KEY_VISIBILITY, visibility)
            .putString(KEY_LAST_EVENT, event)
            .commit()
    }

    private fun invalidate(context: Context, event: String) {
        preferences(context.applicationContext).edit()
            .putBoolean(KEY_INVALIDATED, true)
            .putString(KEY_LAST_EVENT, event)
            .commit()
    }

    private fun installCrashHandler(context: Context) {
        if (crashHandlerInstalled) return
        val previousHandler = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            try {
                invalidate(context, "java_crash")
            } finally {
                if (previousHandler != null) {
                    previousHandler.uncaughtException(thread, throwable)
                } else {
                    Process.killProcess(Process.myPid())
                    exitProcess(10)
                }
            }
        }
        crashHandlerInstalled = true
    }

    private fun isEligiblePreviousSession(
        context: Context,
        session: SessionSnapshot?,
        currentVersion: AppVersion,
    ): Boolean {
        if (session == null || session.invalidated || session.explicitLaunch) {
            return false
        }
        if (session.visibility != VISIBILITY_BACKGROUND) return false
        if (session.versionCode != currentVersion.versionCode ||
            session.lastUpdateTime != currentVersion.lastUpdateTime
        ) {
            return false
        }

        return when {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.R ->
                wasReclaimedInBackground(context, session)
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.N -> true
            else -> false
        }
    }

    @RequiresApi(Build.VERSION_CODES.R)
    private fun wasReclaimedInBackground(
        context: Context,
        session: SessionSnapshot,
    ): Boolean {
        val activityManager = context.getSystemService(ActivityManager::class.java)
            ?: return false
        val exitInfo = try {
            activityManager.getHistoricalProcessExitReasons(
                context.packageName,
                session.processId,
                5,
            ).firstOrNull {
                it.pid == session.processId &&
                    it.timestamp >= session.processStartedAt
            }
        } catch (_: RuntimeException) {
            null
        } ?: return false

        // Reject ambiguous reasons so a task clear is never treated as an
        // ordinary background reclaim merely because an OEM reports OTHER.
        return when (exitInfo.reason) {
            ApplicationExitInfo.REASON_LOW_MEMORY -> true
            ApplicationExitInfo.REASON_SIGNALED ->
                !ActivityManager.isLowMemoryKillReportSupported() &&
                    exitInfo.status == OsConstants.SIGKILL &&
                    exitInfo.importance >=
                    ActivityManager.RunningAppProcessInfo.IMPORTANCE_CACHED
            else -> false
        }
    }

    private fun isLauncherIntent(intent: Intent?): Boolean =
        intent?.action == Intent.ACTION_MAIN &&
            intent.data == null &&
            intent.categories?.contains(Intent.CATEGORY_LAUNCHER) == true

    private fun preferences(context: Context): SharedPreferences =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private fun readSession(preferences: SharedPreferences): SessionSnapshot? {
        if (preferences.getInt(KEY_SCHEMA_VERSION, -1) != SCHEMA_VERSION ||
            !preferences.contains(KEY_PROCESS_ID)
        ) {
            return null
        }
        return SessionSnapshot(
            processId = preferences.getInt(KEY_PROCESS_ID, -1),
            processStartedAt = preferences.getLong(KEY_PROCESS_STARTED_AT, -1L),
            versionCode = preferences.getLong(KEY_VERSION_CODE, -1L),
            lastUpdateTime = preferences.getLong(KEY_LAST_UPDATE_TIME, -1L),
            visibility = preferences.getString(KEY_VISIBILITY, null),
            explicitLaunch = preferences.getBoolean(KEY_EXPLICIT_LAUNCH, true),
            invalidated = preferences.getBoolean(KEY_INVALIDATED, true),
        ).takeIf {
            it.processId > 0 && it.processStartedAt > 0L
        }
    }

    @Suppress("DEPRECATION")
    private fun appVersion(context: Context): AppVersion? = try {
        val info = context.packageManager.getPackageInfo(context.packageName, 0)
        AppVersion(
            versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                info.longVersionCode
            } else {
                info.versionCode.toLong()
            },
            lastUpdateTime = info.lastUpdateTime,
        )
    } catch (_: Exception) {
        null
    }

    private data class SessionSnapshot(
        val processId: Int,
        val processStartedAt: Long,
        val versionCode: Long,
        val lastUpdateTime: Long,
        val visibility: String?,
        val explicitLaunch: Boolean,
        val invalidated: Boolean,
    )

    private data class AppVersion(
        val versionCode: Long,
        val lastUpdateTime: Long,
    )
}
