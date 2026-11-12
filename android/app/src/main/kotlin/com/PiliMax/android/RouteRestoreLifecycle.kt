package com.PiliMax.android

import android.app.Activity
import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.Process
import androidx.annotation.RequiresApi
import java.util.concurrent.Executors
import kotlin.system.exitProcess

/** Native evidence for the one-time, opt-in Dart page restoration. */
internal object RouteRestoreLifecycle {
    const val CHANNEL_NAME = "com.PiliMax.android/route_restore_lifecycle"

    private const val PREFS_NAME = "pilimax_route_restore_lifecycle"
    private const val SCHEMA_VERSION = 1
    private const val KEY_SCHEMA_VERSION = "schema_version"
    private const val KEY_PROCESS_ID = "process_id"
    private const val KEY_PROCESS_STARTED_AT = "process_started_at"
    private const val KEY_TASK_ID = "task_id"
    private const val KEY_VERSION_CODE = "version_code"
    private const val KEY_LAST_UPDATE_TIME = "last_update_time"
    private const val KEY_VISIBILITY = "visibility"
    private const val KEY_EXPLICIT_LAUNCH = "explicit_launch"
    private const val KEY_INVALIDATED = "invalidated"
    private const val KEY_LAST_EVENT = "last_event"
    private const val AWAIT_TIMEOUT_MS = 1800L

    private const val VISIBILITY_FOREGROUND = "foreground"
    private const val VISIBILITY_BACKGROUND = "background"

    private val lock = Any()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val exitReasonExecutor = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "PiliMax-route-restore").apply { isDaemon = true }
    }
    private val waiters = mutableSetOf<DecisionWaiter>()
    private var processInitialized = false
    private var outcome = RouteRestoreOutcome(RouteRestoreDecision.PENDING, "not_initialized")
    private var diagnostics: Map<String, Any?> = emptyMap()
    private var decisionGeneration = 0L
    private var crashHandlerInstalled = false

    fun onActivityCreated(activity: Activity, intent: Intent?, isRecreation: Boolean) {
        val appContext = activity.applicationContext
        val explicitLaunch = !isLauncherIntent(intent)
        val processStartedAt = System.currentTimeMillis()
        var pendingLookup: PendingLookup? = null
        var immediateOutcome: RouteRestoreOutcome? = null

        synchronized(lock) {
            if (processInitialized) {
                // A duplicate Launcher intent must not cancel a pending lookup.
                if (explicitLaunch && !isRecreation) {
                    rejectPendingRestore(appContext, "explicit_activity_launch")
                }
                preferences(appContext).edit()
                    .putInt(KEY_TASK_ID, activity.taskId)
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
            val taskMatches = previousSession?.taskId?.let {
                it >= 0 && it == activity.taskId
            } == true
            val evidence = RouteRestorePolicy.Evidence(
                hasPreviousSession = previousSession != null,
                wasBackground = previousSession?.visibility == VISIBILITY_BACKGROUND,
                invalidated = previousSession?.invalidated != false,
                // An external destination always wins, including when Android
                // also supplies saved activity state for the retained task.
                explicitNewLaunch = explicitLaunch,
                hasTaskEvidence = taskMatches || isRecreation,
                packageUpdated = previousSession != null &&
                    hasPackageUpdateEvidence(previousSession, version),
                apiLevel = Build.VERSION.SDK_INT,
            )
            val generation = ++decisionGeneration
            processInitialized = true
            outcome = RouteRestorePolicy.preflight(evidence)
            diagnostics = mapOf(
                "priorBackground" to evidence.wasBackground,
                "priorInvalidated" to evidence.invalidated,
                "taskMatches" to taskMatches,
                "savedActivityState" to isRecreation,
                "explicitNewLaunch" to evidence.explicitNewLaunch,
                "packageUpdated" to evidence.packageUpdated,
            )

            // Capture the old process and task before replacing its lifecycle record.
            preferences.edit()
                .putInt(KEY_SCHEMA_VERSION, SCHEMA_VERSION)
                .putInt(KEY_PROCESS_ID, Process.myPid())
                .putLong(KEY_PROCESS_STARTED_AT, processStartedAt)
                .putInt(KEY_TASK_ID, activity.taskId)
                .putLong(KEY_VERSION_CODE, version?.versionCode ?: -1L)
                .putLong(KEY_LAST_UPDATE_TIME, version?.lastUpdateTime ?: -1L)
                .putString(KEY_VISIBILITY, VISIBILITY_FOREGROUND)
                .putBoolean(KEY_EXPLICIT_LAUNCH, explicitLaunch)
                .putBoolean(KEY_INVALIDATED, false)
                .putString(KEY_LAST_EVENT, "activity_created")
                .apply()
            installCrashHandler(appContext)

            if (outcome.decision == RouteRestoreDecision.PENDING && previousSession != null) {
                pendingLookup = PendingLookup(previousSession, evidence, generation, processStartedAt)
            } else {
                immediateOutcome = outcome
            }
        }

        immediateOutcome?.let { completeDecision(appContext, it) }
        pendingLookup?.let { lookup ->
            exitReasonExecutor.execute {
                val result = determineRestoreDecision(appContext, lookup)
                completeDecision(appContext, result.outcome, lookup.generation, result.diagnostics)
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

    fun onActivityDestroyed(context: Context, isFinishing: Boolean, isChangingConfigurations: Boolean) {
        if (isFinishing && !isChangingConfigurations) {
            rejectPendingRestore(context, "activity_finished")
            invalidate(context, "activity_finished")
        }
    }

    fun onNewIntent(context: Context, intent: Intent?) {
        val explicitLaunch = !isLauncherIntent(intent)
        if (explicitLaunch) rejectPendingRestore(context, "explicit_new_intent")
        preferences(context.applicationContext).edit()
            .putBoolean(KEY_EXPLICIT_LAUNCH, explicitLaunch)
            .putString(KEY_LAST_EVENT, if (explicitLaunch) "new_intent" else "launcher_intent")
            .commit()
    }

    fun getRestoreDecision(): String = synchronized(lock) { outcome.decision.wireValue }

    fun getRestoreDiagnostics(): Map<String, Any?> = synchronized(lock) { decisionSnapshot() }

    /** Wait without blocking the UI thread; a timeout stays pending, never implies safe reclaim. */
    fun awaitRestoreDecision(onComplete: (Map<String, Any?>) -> Unit) {
        val waiter = DecisionWaiter(onComplete)
        val immediate = synchronized(lock) {
            if (outcome.decision == RouteRestoreDecision.PENDING) {
                waiters.add(waiter)
                null
            } else {
                decisionSnapshot()
            }
        }
        if (immediate != null) {
            onComplete(immediate)
            return
        }
        mainHandler.postDelayed({
            val snapshot = synchronized(lock) {
                if (waiters.remove(waiter)) decisionSnapshot() else null
            }
            if (snapshot != null) onComplete(snapshot)
        }, AWAIT_TIMEOUT_MS)
    }

    fun markTaskRemoved(context: Context) {
        rejectPendingRestore(context, "task_removed")
        invalidate(context, "task_removed")
    }

    fun markIntentionalExit(context: Context) {
        rejectPendingRestore(context, "intentional_exit")
        invalidate(context, "intentional_exit")
    }

    private fun rejectPendingRestore(context: Context, reason: String) {
        synchronized(lock) { decisionGeneration++ }
        completeDecision(context, RouteRestoreOutcome(RouteRestoreDecision.REJECT, reason))
    }

    private fun completeDecision(
        context: Context,
        result: RouteRestoreOutcome,
        generation: Long? = null,
        details: Map<String, Any?> = emptyMap(),
    ) {
        val callbacks: List<DecisionWaiter>
        synchronized(lock) {
            if (generation != null && generation != decisionGeneration) return
            outcome = result
            diagnostics = diagnostics + details
            callbacks = waiters.toList()
            waiters.clear()
            // The recorder only queues I/O. Enqueue while decisions are ordered
            // so a later explicit rejection cannot be overwritten by stale diagnostics.
            PlaybackExitSnapshot.recordRestoreDecision(context, result.decision.name, result.reason)
        }
        if (callbacks.isNotEmpty()) {
            mainHandler.post {
                // An explicit intent may reject restoration while this reply
                // is queued behind onNewIntent on the main thread.
                val snapshot = synchronized(lock) { decisionSnapshot() }
                callbacks.forEach { it.onComplete(snapshot) }
            }
        }
    }

    private fun decisionSnapshot(): Map<String, Any?> = diagnostics + mapOf(
        "decision" to outcome.decision.wireValue,
        "reason" to outcome.reason,
    )

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
                rejectPendingRestore(context, "java_crash")
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

    private fun determineRestoreDecision(context: Context, lookup: PendingLookup): LookupResult {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            return LookupResult(RouteRestorePolicy.unavailableHistory(lookup.evidence, "legacy_android"))
        }
        return restoreDecisionFromExitInfo(context, lookup)
    }

    @RequiresApi(Build.VERSION_CODES.R)
    private fun restoreDecisionFromExitInfo(context: Context, lookup: PendingLookup): LookupResult {
        val activityManager = context.getSystemService(ActivityManager::class.java)
            ?: return LookupResult(
                RouteRestorePolicy.unavailableHistory(lookup.evidence, "activity_manager_unavailable"),
            )
        return try {
            val exitInfo = activityManager.getHistoricalProcessExitReasons(
                context.packageName,
                lookup.session.processId,
                5,
            ).filter {
                it.pid == lookup.session.processId &&
                    it.timestamp >= lookup.session.processStartedAt &&
                    it.timestamp <= lookup.processStartedAt
            }.maxByOrNull { it.timestamp }
            val lmkSupported = ActivityManager.isLowMemoryKillReportSupported()
            LookupResult(
                RouteRestorePolicy.fromExit(
                    lookup.evidence,
                    exitInfo?.reason,
                    exitInfo?.status,
                    lmkSupported,
                ),
                mapOf(
                    "exitReason" to exitInfo?.reason,
                    "exitStatus" to exitInfo?.status,
                    "exitImportance" to exitInfo?.importance,
                    "lowMemoryKillReportSupported" to lmkSupported,
                ),
            )
        } catch (_: RuntimeException) {
            LookupResult(RouteRestorePolicy.unavailableHistory(lookup.evidence, "exit_history_unavailable"))
        } catch (_: LinkageError) {
            LookupResult(RouteRestorePolicy.unavailableHistory(lookup.evidence, "exit_history_unsupported"))
        }
    }

    private fun hasPackageUpdateEvidence(session: SessionSnapshot, currentVersion: AppVersion?): Boolean =
        session.versionCode >= 0L && session.lastUpdateTime > 0L && currentVersion != null &&
            currentVersion.versionCode >= 0L && currentVersion.lastUpdateTime > 0L &&
            (session.versionCode != currentVersion.versionCode ||
                session.lastUpdateTime != currentVersion.lastUpdateTime)

    private fun isLauncherIntent(intent: Intent?): Boolean =
        intent?.action == Intent.ACTION_MAIN && intent.data == null &&
            intent.categories?.contains(Intent.CATEGORY_LAUNCHER) == true

    private fun preferences(context: Context): SharedPreferences =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private fun readSession(preferences: SharedPreferences): SessionSnapshot? {
        if (preferences.getInt(KEY_SCHEMA_VERSION, -1) != SCHEMA_VERSION ||
            !preferences.contains(KEY_PROCESS_ID)
        ) return null
        return SessionSnapshot(
            processId = preferences.getInt(KEY_PROCESS_ID, -1),
            processStartedAt = preferences.getLong(KEY_PROCESS_STARTED_AT, -1L),
            taskId = preferences.getInt(KEY_TASK_ID, -1),
            versionCode = preferences.getLong(KEY_VERSION_CODE, -1L),
            lastUpdateTime = preferences.getLong(KEY_LAST_UPDATE_TIME, -1L),
            visibility = preferences.getString(KEY_VISIBILITY, null),
            invalidated = preferences.getBoolean(KEY_INVALIDATED, true),
        ).takeIf { it.processId > 0 && it.processStartedAt > 0L }
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
        val taskId: Int,
        val versionCode: Long,
        val lastUpdateTime: Long,
        val visibility: String?,
        val invalidated: Boolean,
    )

    private data class AppVersion(val versionCode: Long, val lastUpdateTime: Long)

    private data class PendingLookup(
        val session: SessionSnapshot,
        val evidence: RouteRestorePolicy.Evidence,
        val generation: Long,
        val processStartedAt: Long,
    )

    private data class LookupResult(
        val outcome: RouteRestoreOutcome,
        val diagnostics: Map<String, Any?> = emptyMap(),
    )

    private class DecisionWaiter(val onComplete: (Map<String, Any?>) -> Unit)
}
