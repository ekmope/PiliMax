package com.PiliMax.android

/** Intent facts captured before Flutter plugins may replace an Activity's Intent. */
internal data class RouteRestoreLaunchEvidence(
    val isMainAction: Boolean,
    val hasData: Boolean,
    val hasLauncherCategory: Boolean,
    val launchedFromHistory: Boolean,
)

/** Distinguishes reopening a retained task from navigating to a new destination. */
internal object RouteRestoreLaunchPolicy {
    fun isExplicitActivityCreation(intent: RouteRestoreLaunchEvidence): Boolean =
        // The data on a history launch belongs to its old task, not a new link.
        // This only affects restoration; the old Intent is never replayed.
        !intent.launchedFromHistory && !isLauncher(intent)

    fun isExplicitNewIntent(intent: RouteRestoreLaunchEvidence): Boolean =
        // A newly delivered destination wins even if its caller sets a history flag.
        !isLauncher(intent)

    private fun isLauncher(intent: RouteRestoreLaunchEvidence): Boolean =
        intent.isMainAction && !intent.hasData && intent.hasLauncherCategory
}
