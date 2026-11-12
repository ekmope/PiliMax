package com.PiliMax.android

internal enum class RouteRestoreDecision(val wireValue: String) {
    PENDING("pending"),
    RESTORE("restore"),
    REJECT("reject"),
    UNKNOWN("unknown"),
}

internal data class RouteRestoreOutcome(
    val decision: RouteRestoreDecision,
    val reason: String,
)

/** Pure policy: an unclassified exit alone is never evidence of system reclaim. */
internal object RouteRestorePolicy {
    // Added in SDK 37.2. Match returned wire values without requiring its
    // compileSdk constants or assuming every SDK_INT=37 device supports them.
    private const val REASON_MEMORY_LIMITER = 17
    private const val REASON_ANOMALY = 18

    data class Evidence(
        val hasPreviousSession: Boolean,
        val wasBackground: Boolean,
        val invalidated: Boolean,
        val explicitNewLaunch: Boolean,
        val hasTaskEvidence: Boolean,
        val packageUpdated: Boolean,
        val apiLevel: Int,
    )

    fun preflight(evidence: Evidence): RouteRestoreOutcome = with(evidence) {
        when {
            explicitNewLaunch -> reject("explicit_launch")
            !hasPreviousSession -> reject("no_previous_session")
            invalidated -> reject("previous_session_invalidated")
            !wasBackground -> reject("previous_session_not_background")
            else -> RouteRestoreOutcome(RouteRestoreDecision.PENDING, "exit_lookup_pending")
        }
    }

    // These are the public ApplicationExitInfo reason values.
    // Keeping this policy Android-free allows testing its complete decision matrix.
    fun fromExit(
        evidence: Evidence,
        reason: Int?,
        status: Int? = null,
        lowMemoryKillReportSupported: Boolean? = null,
    ): RouteRestoreOutcome {
        preflight(evidence).let {
            if (it.decision != RouteRestoreDecision.PENDING) return it
        }
        return when (reason) {
            3, 12, 14, 16 -> restore("system_reclaim_$reason")
            1, 4, 5, 6, 7, 8, 9, 11, 15, REASON_ANOMALY -> reject("unsafe_exit_$reason")
            REASON_MEMORY_LIMITER -> fallback(evidence, "memory_limiter")
            10 -> if (evidence.apiLevel < 34 && evidence.packageUpdated) {
                restore("package_updated_legacy")
            } else {
                reject("user_requested_exit")
            }
            2 -> when {
                status != 9 -> reject("non_reclaim_signal")
                lowMemoryKillReportSupported == false -> restore("sigkill_without_lmk_reporting")
                else -> fallback(evidence, "ambiguous_sigkill")
            }
            null -> if (evidence.packageUpdated) {
                restore("package_updated_without_exit_record")
            } else {
                fallback(evidence, "missing_exit_record")
            }
            0, 13 -> fallback(evidence, "unclassified_exit_$reason")
            // Do not assume new SDK / OEM reasons are safe to restore after.
            else -> RouteRestoreOutcome(RouteRestoreDecision.UNKNOWN, "unsupported_exit_$reason")
        }
    }

    fun unavailableHistory(evidence: Evidence, reason: String): RouteRestoreOutcome {
        preflight(evidence).let {
            if (it.decision != RouteRestoreDecision.PENDING) return it
        }
        return fallback(evidence, reason)
    }

    private fun fallback(evidence: Evidence, reason: String): RouteRestoreOutcome =
        if (evidence.hasTaskEvidence) {
            restore("${reason}_retained_task")
        } else {
            RouteRestoreOutcome(RouteRestoreDecision.UNKNOWN, reason)
        }

    private fun restore(reason: String) = RouteRestoreOutcome(RouteRestoreDecision.RESTORE, reason)
    private fun reject(reason: String) = RouteRestoreOutcome(RouteRestoreDecision.REJECT, reason)
}
