package com.PiliMax.android

/** Standalone policy regression test: compile with RouteRestorePolicy.kt, then run main. */
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
    println("RouteRestorePolicy: $checked cases passed")
}
