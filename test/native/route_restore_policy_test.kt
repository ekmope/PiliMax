package com.PiliMax.android

/** Compile with RouteRestorePolicy.kt and RouteRestoreLaunchPolicy.kt, then run main. */
fun main() {
    val background = RouteRestorePolicy.Evidence(
        hasPreviousSession = true,
        wasBackground = true,
        invalidated = false,
        explicitNewLaunch = false,
        hasTaskEvidence = true,
        packageUpdated = false,
        apiLevel = 37,
    )
    var checked = 0
    fun expectDecision(
        expected: RouteRestoreDecision,
        actual: RouteRestoreOutcome,
        scenario: String,
    ) {
        check(actual.decision == expected) { "$scenario: expected $expected, got $actual" }
        checked++
    }

    expectDecision(RouteRestoreDecision.PENDING, RouteRestorePolicy.preflight(background), "valid background")
    for (evidence in listOf(
        background.copy(hasPreviousSession = false),
        background.copy(wasBackground = false),
        background.copy(invalidated = true),
        background.copy(explicitNewLaunch = true),
    )) {
        expectDecision(RouteRestoreDecision.REJECT, RouteRestorePolicy.fromExit(evidence, 3), "preflight wins")
    }
    for (reason in listOf(3, 12, 14, 16)) {
        expectDecision(RouteRestoreDecision.RESTORE, RouteRestorePolicy.fromExit(background, reason), "system reason $reason")
    }
    for (reason in listOf(1, 4, 5, 6, 7, 8, 9, 10, 11, 15, 18)) {
        expectDecision(RouteRestoreDecision.REJECT, RouteRestorePolicy.fromExit(background, reason), "unsafe reason $reason")
    }
    for (reason in listOf(null, 0, 13)) {
        expectDecision(RouteRestoreDecision.RESTORE, RouteRestorePolicy.fromExit(background, reason), "retained task, reason $reason")
        expectDecision(
            RouteRestoreDecision.UNKNOWN,
            RouteRestorePolicy.fromExit(background.copy(hasTaskEvidence = false), reason),
            "new task, reason $reason",
        )
    }
    expectDecision(RouteRestoreDecision.REJECT, RouteRestorePolicy.fromExit(background, 2, 11), "SIGSEGV is unsafe")
    expectDecision(RouteRestoreDecision.RESTORE, RouteRestorePolicy.fromExit(background, 2, 9, true), "ambiguous SIGKILL, retained task")
    expectDecision(
        RouteRestoreDecision.UNKNOWN,
        RouteRestorePolicy.fromExit(background.copy(hasTaskEvidence = false), 2, 9, true),
        "ambiguous SIGKILL, new task",
    )
    expectDecision(
        RouteRestoreDecision.RESTORE,
        RouteRestorePolicy.fromExit(background.copy(hasTaskEvidence = false), 2, 9, false),
        "documented SIGKILL on a device without LMK reports",
    )
    expectDecision(RouteRestoreDecision.RESTORE, RouteRestorePolicy.fromExit(background, 17), "memory limiter, retained task")
    expectDecision(
        RouteRestoreDecision.UNKNOWN,
        RouteRestorePolicy.fromExit(background.copy(hasTaskEvidence = false), 17),
        "memory limiter, new task",
    )
    expectDecision(RouteRestoreDecision.UNKNOWN, RouteRestorePolicy.fromExit(background, 999), "future reason")
    expectDecision(
        RouteRestoreDecision.RESTORE,
        RouteRestorePolicy.fromExit(background.copy(apiLevel = 33, packageUpdated = true), 10),
        "legacy package update",
    )
    expectDecision(
        RouteRestoreDecision.REJECT,
        RouteRestorePolicy.fromExit(background.copy(packageUpdated = true), 10),
        "modern user exit still rejects after update",
    )
    expectDecision(
        RouteRestoreDecision.RESTORE,
        RouteRestorePolicy.fromExit(background.copy(packageUpdated = true, hasTaskEvidence = false), null),
        "package update without exit record",
    )
    expectDecision(
        RouteRestoreDecision.RESTORE,
        RouteRestorePolicy.unavailableHistory(background.copy(apiLevel = 29), "legacy_android"),
        "legacy retained task",
    )
    expectDecision(
        RouteRestoreDecision.UNKNOWN,
        RouteRestorePolicy.unavailableHistory(background.copy(apiLevel = 29, hasTaskEvidence = false), "legacy_android"),
        "legacy new task does not imply reclaim",
    )

    val foregroundUpdate = background.copy(wasBackground = false, packageUpdated = true)
    expectDecision(
        RouteRestoreDecision.PENDING,
        RouteRestorePolicy.preflight(foregroundUpdate),
        "a verified update can stop the visible process without onStop",
    )
    expectDecision(
        RouteRestoreDecision.RESTORE,
        RouteRestorePolicy.fromExit(foregroundUpdate, 16),
        "foreground package update",
    )
    expectDecision(
        RouteRestoreDecision.RESTORE,
        RouteRestorePolicy.fromExit(foregroundUpdate.copy(hasTaskEvidence = false), null),
        "verified foreground update without exit record",
    )
    for (reason in listOf(1, 4, 5, 6, 7, 8, 9, 10, 11, 15, 18)) {
        expectDecision(
            RouteRestoreDecision.REJECT,
            RouteRestorePolicy.fromExit(foregroundUpdate, reason),
            "an update must not override unsafe exit $reason",
        )
    }
    for (evidence in listOf(
        foregroundUpdate.copy(hasPreviousSession = false),
        foregroundUpdate.copy(invalidated = true),
        foregroundUpdate.copy(explicitNewLaunch = true),
    )) {
        expectDecision(
            RouteRestoreDecision.REJECT,
            RouteRestorePolicy.fromExit(evidence, 16),
            "an update must not override an explicit rejection",
        )
    }
    expectDecision(
        RouteRestoreDecision.REJECT,
        RouteRestorePolicy.preflight(background.copy(wasBackground = false)),
        "foreground death without a verified package update remains unsafe",
    )
    expectDecision(
        RouteRestoreDecision.UNKNOWN,
        RouteRestorePolicy.fromExit(foregroundUpdate.copy(hasTaskEvidence = false), 13),
        "a verified update alone does not classify an OEM OTHER exit",
    )

    val launcher = RouteRestoreLaunchEvidence(
        isMainAction = true,
        hasData = false,
        hasLauncherCategory = true,
        launchedFromHistory = false,
    )
    val externalLink = launcher.copy(isMainAction = false, hasData = true, hasLauncherCategory = false)
    val historyLauncher = launcher.copy(launchedFromHistory = true)
    val historyLink = externalLink.copy(launchedFromHistory = true)
    // This is what audio_service leaves on the Activity after attaching on a
    // history launch. Only the pre-super capture retains its task launch facts.
    val rewrittenByPlugin = launcher.copy(hasLauncherCategory = false)
    fun expectLaunch(
        intent: RouteRestoreLaunchEvidence,
        isNewIntent: Boolean,
        expected: RouteRestoreDecision,
        scenario: String,
    ) {
        val explicit = if (isNewIntent) {
            RouteRestoreLaunchPolicy.isExplicitNewIntent(intent)
        } else {
            RouteRestoreLaunchPolicy.isExplicitActivityCreation(intent)
        }
        expectDecision(
            expected,
            RouteRestorePolicy.fromExit(background.copy(explicitNewLaunch = explicit), 13),
            scenario,
        )
    }
    expectLaunch(launcher, false, RouteRestoreDecision.RESTORE, "fresh launcher")
    expectLaunch(externalLink, false, RouteRestoreDecision.REJECT, "fresh external destination")
    expectLaunch(historyLauncher, false, RouteRestoreDecision.RESTORE, "captured launcher from recents")
    expectLaunch(historyLink, false, RouteRestoreDecision.RESTORE, "old deep link from recents is not a fresh destination")
    expectLaunch(rewrittenByPlugin, false, RouteRestoreDecision.REJECT, "post-plugin Intent cannot establish launcher origin")
    expectLaunch(launcher, true, RouteRestoreDecision.RESTORE, "duplicate launcher must not cancel lookup")
    expectLaunch(externalLink, true, RouteRestoreDecision.REJECT, "new external destination wins")
    expectLaunch(historyLink, true, RouteRestoreDecision.REJECT, "onNewIntent does not trust caller history flags")
    expectLaunch(launcher.copy(hasData = true), false, RouteRestoreDecision.REJECT, "a launcher-shaped destination with data is explicit")
    expectLaunch(rewrittenByPlugin.copy(isMainAction = false), false, RouteRestoreDecision.REJECT, "missing launch facts are not evidence of task restoration")
    for (launch in listOf(historyLauncher, historyLink)) {
        expectDecision(
            RouteRestoreDecision.REJECT,
            RouteRestorePolicy.fromExit(background.copy(
                invalidated = true,
                explicitNewLaunch = RouteRestoreLaunchPolicy.isExplicitActivityCreation(launch),
            ), 13),
            "history must not revive an invalidated session",
        )
    }
    println("RouteRestorePolicy: $checked cases passed")
}
