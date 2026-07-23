package com.PiliMax.android

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import android.os.Process
import androidx.annotation.RequiresApi
import java.util.concurrent.Executors
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
    private val exitReasonExecutor = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "PiliMax-route-restore").apply { isDaemon = true }
    }
    private var processInitialized = false
    private var restoreDecision = RestoreDecision.UNAVAILABLE
    private var decisionGeneration = 0L
    private var crashHandlerInstalled = false

    fun onActivityCreated(
        context: Context,
        intent: Intent?,
        isRecreation: Boolean,
    ) {
        val appContext = context.applicationContext
        val explicitLaunch = !isLauncherIntent(intent)
        var pendingLookup: PendingLookup? = null

        synchronized(lock) {
            if (processInitialized) {
                if (!isRecreation) {
                    rejectPendingRestoreLocked()
                }
                preferences(appContext).edit()
                    .putBoolean(KEY_EXPLICIT_LAUNCH, explicitLaunch)
                    .putString(
                        KEY_LAST_EVENT,
                        if (isRecreation) "activity_recreated" else "activity_created_again",
                    )
                    .apply()
                return
            }

            val preferences = preferences(appContext)
            val previousSession = readSession(preferences)
            val version = appVersion(appContext)
            val generation = ++decisionGeneration

            processInitialized = true
            restoreDecision = preflightDecision(previousSession, explicitLaunch)

            // Capture the previous process before replacing its lifecycle record.
            preferences.edit()
                .putInt(KEY_SCHEMA_VERSION, SCHEMA_VERSION)
                .putInt(KEY_PROCESS_ID, Process.myPid())
                .putLong(KEY_PROCESS_STARTED_AT, System.currentTimeMillis())
                .putLong(KEY_VERSION_CODE, version?.versionCode ?: -1L)
                .putLong(KEY_LAST_UPDATE_TIME, version?.lastUpdateTime ?: -1L)
                .putString(KEY_VISIBILITY, VISIBILITY_FOREGROUND)
                .putBoolean(KEY_EXPLICIT_LAUNCH, explicitLaunch)
                .putBoolean(KEY_INVALIDATED, false)
                .putString(KEY_LAST_EVENT, "activity_created")
                .apply()

            installCrashHandler(appContext)

            if (restoreDecision == RestoreDecision.UNAVAILABLE && previousSession != null) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    pendingLookup = PendingLookup(previousSession, version, generation)
                } else if (hasPackageUpdateEvidence(previousSession, version)) {
                    restoreDecision = RestoreDecision.RESTORE
                }
            }
        }

        pendingLookup?.let { lookup ->
            exitReasonExecutor.execute {
                val decision = determineRestoreDecision(appContext, lookup)
                synchronized(lock) {
                    if (lookup.generation == decisionGeneration &&
                        restoreDecision != RestoreDecision.REJECT
                    ) {
                        restoreDecision = decision
                    }
                }
            }
        }
    }

    fun onActivityStarted(context: Context) {
        preferences(context.applicationContext).edit()
            .putString(KEY_VISIBILITY, VISIBILITY_FOREGROUND)
            .putBoolean(KEY_INVALIDATED, false)
            .putString(KEY_LAST_EVENT, "activity_started")
            .apply()
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
            rejectPendingRestore()
            invalidate(context, "activity_finished")
        }
    }

    fun onNewIntent(context: Context, intent: Intent?) {
        val explicitLaunch = !isLauncherIntent(intent)
        val appContext = context.applicationContext
        rejectPendingRestore()
        preferences(appContext).edit()
            .putBoolean(KEY_EXPLICIT_LAUNCH, explicitLaunch)
            .putString(KEY_LAST_EVENT, "new_intent")
            .commit()
    }

    fun getRestoreDecision(): String = synchronized(lock) {
        restoreDecision.wireValue
    }

    fun markTaskRemoved(context: Context) {
        rejectPendingRestore()
        invalidate(context, "task_removed")
    }

    fun markIntentionalExit(context: Context) {
        rejectPendingRestore()
        invalidate(context, "intentional_exit")
    }

    private fun rejectPendingRestore() {
        synchronized(lock) {
            rejectPendingRestoreLocked()
        }
    }

    private fun rejectPendingRestoreLocked() {
        restoreDecision = RestoreDecision.REJECT
        decisionGeneration++
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
                rejectPendingRestore()
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

    private fun preflightDecision(
        session: SessionSnapshot?,
        explicitLaunch: Boolean,
    ): RestoreDecision = when {
        explicitLaunch -> RestoreDecision.REJECT
        session == null -> RestoreDecision.REJECT
        session.invalidated -> RestoreDecision.REJECT
        session.visibility != VISIBILITY_BACKGROUND -> RestoreDecision.REJECT
        else -> RestoreDecision.UNAVAILABLE
    }

    private fun determineRestoreDecision(
        context: Context,
        lookup: PendingLookup,
    ): RestoreDecision {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            return RestoreDecision.UNAVAILABLE
        }

        return restoreDecisionFromExitInfo(context, lookup)
    }

    @RequiresApi(Build.VERSION_CODES.R)
    private fun restoreDecisionFromExitInfo(
        context: Context,
        lookup: PendingLookup,
    ): RestoreDecision {
        val activityManager = context.getSystemService(ActivityManager::class.java)
            ?: return RestoreDecision.UNAVAILABLE
        val exitInfos = try {
            activityManager.getHistoricalProcessExitReasons(
                context.packageName,
                lookup.session.processId,
                5,
            }
        } catch (_: RuntimeException) {
            return RestoreDecision.UNAVAILABLE
        }
        val exitInfo = exitInfos.firstOrNull {
            it.pid == lookup.session.processId &&
                it.timestamp >= lookup.session.processStartedAt
        } ?: return if (hasPackageUpdateEvidence(lookup.session, lookup.currentVersion)) {
            RestoreDecision.RESTORE
        } else {
            RestoreDecision.UNAVAILABLE
        }

        val reason = exitInfo.reason
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            reason == ApplicationExitInfo.REASON_FREEZER
        ) {
            return RestoreDecision.RESTORE
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            when (reason) {
                ApplicationExitInfo.REASON_PACKAGE_UPDATED ->
                    return RestoreDecision.RESTORE
                ApplicationExitInfo.REASON_PACKAGE_STATE_CHANGE ->
                    return RestoreDecision.REJECT
            }
        }
        return when (reason) {
            ApplicationExitInfo.REASON_LOW_MEMORY,
            ApplicationExitInfo.REASON_DEPENDENCY_DIED -> RestoreDecision.RESTORE
            ApplicationExitInfo.REASON_EXIT_SELF,
            ApplicationExitInfo.REASON_CRASH,
            ApplicationExitInfo.REASON_CRASH_NATIVE,
            ApplicationExitInfo.REASON_ANR,
            ApplicationExitInfo.REASON_INITIALIZATION_FAILURE,
            ApplicationExitInfo.REASON_PERMISSION_CHANGE,
            ApplicationExitInfo.REASON_EXCESSIVE_RESOURCE_USAGE,
            ApplicationExitInfo.REASON_USER_STOPPED -> RestoreDecision.REJECT
            ApplicationExitInfo.REASON_USER_REQUESTED -> {
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE &&
                    hasPackageUpdateEvidence(lookup.session, lookup.currentVersion)
                ) {
                    RestoreDecision.RESTORE
                } else {
                    RestoreDecision.REJECT
                }
            }
            ApplicationExitInfo.REASON_UNKNOWN,
            ApplicationExitInfo.REASON_SIGNALED,
            ApplicationExitInfo.REASON_OTHER -> RestoreDecision.UNAVAILABLE
            else -> RestoreDecision.UNAVAILABLE
        }
    }

    private fun hasPackageUpdateEvidence(
        session: SessionSnapshot,
        currentVersion: AppVersion?,
    ): Boolean = session.versionCode >= 0L &&
        session.lastUpdateTime > 0L &&
        currentVersion != null &&
        currentVersion.versionCode >= 0L &&
        currentVersion.lastUpdateTime > 0L &&
        (session.versionCode != currentVersion.versionCode ||
            session.lastUpdateTime != currentVersion.lastUpdateTime)

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

    private data class PendingLookup(
        val session: SessionSnapshot,
        val currentVersion: AppVersion?,
        val generation: Long,
    )

    private enum class RestoreDecision(val wireValue: String) {
        RESTORE("restore"),
        REJECT("reject"),
        UNAVAILABLE("unavailable"),
    }
}
