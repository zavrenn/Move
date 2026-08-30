package com.med.move

import java.time.Duration
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZonedDateTime
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class NativePolicyTest {
    private val zone = ZoneId.of("Africa/Casablanca")

    @Test
    fun fallbackWindowTracksFromEightAndCannotAlertBeforeNine() {
        val window = SmartAlertPolicy.activeWindow(
            LocalDate.of(2026, 8, 30),
            zone,
            wakeMinutes = null,
            bedtimeMinutes = null,
        )

        assertEquals(8, window.start.hour)
        assertEquals(22, window.end.hour)
        assertEquals(9, window.earliestAlert.hour)
        assertFalse(window.usesSamsungTarget)
        assertTrue(window.isAlertable)
    }

    @Test
    fun samsungWindowStartsWakePlusOneAndAlertsWakePlusTwo() {
        val window = SmartAlertPolicy.activeWindow(
            LocalDate.of(2026, 8, 30),
            zone,
            wakeMinutes = 7 * 60 + 15,
            bedtimeMinutes = 23 * 60 + 30,
        )

        assertEquals(8 * 60 + 15, window.start.hour * 60 + window.start.minute)
        assertEquals(9 * 60 + 15, window.earliestAlert.hour * 60 + window.earliestAlert.minute)
        assertEquals(22 * 60 + 30, window.end.hour * 60 + window.end.minute)
        assertTrue(window.usesSamsungTarget)
    }

    @Test
    fun samsungWindowSupportsBedtimeAfterMidnight() {
        val date = LocalDate.of(2026, 8, 30)
        val window = SmartAlertPolicy.activeWindow(
            date,
            zone,
            wakeMinutes = 8 * 60,
            bedtimeMinutes = 2 * 60,
        )

        assertEquals(date.atTime(9, 0).atZone(zone), window.start)
        assertEquals(date.plusDays(1).atTime(1, 0).atZone(zone), window.end)
    }

    @Test
    fun afterMidnightUsesPriorDayWindowWhenStillActive() {
        val now = ZonedDateTime.of(2026, 8, 31, 0, 30, 0, 0, zone)
        val window = SmartAlertPolicy.activeWindowForMoment(
            now,
            wakeMinutes = 8 * 60,
            bedtimeMinutes = 2 * 60,
        )

        assertEquals(LocalDate.of(2026, 8, 30), window.start.toLocalDate())
        assertTrue(now.isBefore(window.end))
    }

    @Test
    fun degenerateSamsungWindowStaysQuietInsteadOfUsingFallback() {
        val window = SmartAlertPolicy.activeWindow(
            LocalDate.of(2026, 8, 30),
            zone,
            wakeMinutes = 8 * 60,
            bedtimeMinutes = 10 * 60,
        )

        assertTrue(window.usesSamsungTarget)
        assertFalse(window.isAlertable)
        assertEquals(9, window.start.hour)
        assertEquals(9, window.end.hour)
    }

    @Test
    fun targetTimesRemainWallClockTimesAcrossDstChange() {
        val paris = ZoneId.of("Europe/Paris")
        val window = SmartAlertPolicy.activeWindow(
            LocalDate.of(2026, 3, 29),
            paris,
            wakeMinutes = 7 * 60,
            bedtimeMinutes = 23 * 60,
        )

        assertEquals(8, window.start.hour)
        assertEquals(22, window.end.hour)
    }

    @Test
    fun adaptiveThresholdUsesRemainingGoalAndHours() {
        val end = 12L * Duration.ofHours(1).toMillis()
        val now = 2L * Duration.ofHours(1).toMillis()

        assertEquals(
            200,
            SmartAlertPolicy.adaptiveStepThreshold(0, 8000, now, end),
        )
    }

    @Test
    fun adaptiveThresholdClampsAtBothBounds() {
        val hour = Duration.ofHours(1).toMillis()

        assertEquals(100, SmartAlertPolicy.adaptiveStepThreshold(7000, 8000, 0L, 10L * hour))
        assertEquals(400, SmartAlertPolicy.adaptiveStepThreshold(0, 8000, 0L, hour))
        assertEquals(100, SmartAlertPolicy.adaptiveStepThreshold(8000, 8000, 0L, hour))
    }

    @Test
    fun adaptiveThresholdRoundsUp() {
        val tenHours = Duration.ofHours(10).toMillis()

        assertEquals(101, SmartAlertPolicy.adaptiveStepThreshold(0, 4001, 0L, tenHours))
    }

    @Test
    fun firstReliableCheckBuildsBaselineForAFullHour() {
        val hour = Duration.ofHours(1).toMillis()
        val decision = SmartAlertPolicy.evaluate(baseInput(now = 0L, baseline = null))

        assertEquals(SmartAlertPolicy.Action.BASELINE, decision.action)
        assertEquals(1000, decision.baselineSteps)
        assertEquals(0L, decision.inactiveSince)
        assertEquals(Duration.ofMinutes(15).toMillis(), decision.nextCheckAt)
    }

    @Test
    fun insufficientStepsAlertOnlyAfterFullInactiveHour() {
        val hour = Duration.ofHours(1).toMillis()
        val before = SmartAlertPolicy.evaluate(
            baseInput(now = hour - 1L, baseline = 1000, inactiveSince = 0L),
        )
        val eligible = SmartAlertPolicy.evaluate(
            baseInput(now = hour, baseline = 1000, inactiveSince = 0L),
        )

        assertEquals(SmartAlertPolicy.Action.WAIT, before.action)
        assertEquals(SmartAlertPolicy.Action.ALERT, eligible.action)
    }

    @Test
    fun enoughNewStepsResetInactivity() {
        val hour = Duration.ofHours(1).toMillis()
        val decision = SmartAlertPolicy.evaluate(
            baseInput(
                now = hour,
                baseline = 1000,
                inactiveSince = 0L,
                currentSteps = 1200,
            ),
        )

        assertEquals(SmartAlertPolicy.Action.ACTIVITY, decision.action)
        assertEquals(1200, decision.baselineSteps)
        assertEquals(hour, decision.inactiveSince)
    }

    @Test
    fun movementLogResetsInactivity() {
        val hour = Duration.ofHours(1).toMillis()
        val decision = SmartAlertPolicy.evaluate(
            baseInput(
                now = hour,
                baseline = 1000,
                inactiveSince = 0L,
                movementActivity = true,
            ),
        )

        assertEquals(SmartAlertPolicy.Action.ACTIVITY, decision.action)
        assertEquals(hour, decision.inactiveSince)
        assertEquals("activity_detected", decision.deferReason)
    }

    @Test
    fun completingBothGoalsStopsAlerts() {
        val decision = SmartAlertPolicy.evaluate(
            baseInput(
                now = Duration.ofHours(1).toMillis(),
                baseline = 8000,
                inactiveSince = 0L,
                currentSteps = 8000,
                movements = 3,
            ),
        )

        assertEquals(SmartAlertPolicy.Action.GOALS_COMPLETE, decision.action)
        assertNull(decision.nextCheckAt)
    }

    @Test
    fun completedStepGoalStillRequiresRealStepActivityWhenMovementRemains() {
        val hour = Duration.ofHours(1).toMillis()
        val decision = SmartAlertPolicy.evaluate(
            baseInput(
                now = hour,
                baseline = 8000,
                inactiveSince = 0L,
                currentSteps = 8100,
                movements = 1,
            ),
        )

        assertEquals(100, decision.adaptiveThreshold)
        assertEquals(SmartAlertPolicy.Action.ACTIVITY, decision.action)
    }

    @Test
    fun cooldownPreventsRepeatForTwoHours() {
        val hour = Duration.ofHours(1).toMillis()
        val decision = SmartAlertPolicy.evaluate(
            baseInput(
                now = 2L * hour,
                baseline = 1000,
                inactiveSince = 0L,
                lastAlertAt = hour,
            ),
        )

        assertEquals(SmartAlertPolicy.Action.DEFER, decision.action)
        assertEquals("cooldown", decision.deferReason)
        assertEquals(2L * hour + Duration.ofMinutes(15).toMillis(), decision.nextCheckAt)
    }

    @Test
    fun cooldownAllowsAlertAtExactTwoHourBoundary() {
        val hour = Duration.ofHours(1).toMillis()
        val decision = SmartAlertPolicy.evaluate(
            baseInput(
                now = 3L * hour,
                baseline = 1000,
                inactiveSince = 0L,
                lastAlertAt = hour,
            ),
        )

        assertEquals(SmartAlertPolicy.Action.ALERT, decision.action)
    }

    @Test
    fun cooldownContinuesAcrossLocalMidnight() {
        val lastAlert = ZonedDateTime.of(2026, 8, 30, 23, 50, 0, 0, zone)
        val now = lastAlert.plusHours(1)
        val decision = SmartAlertPolicy.evaluate(
            SmartAlertPolicy.Input(
                now = now.toInstant().toEpochMilli(),
                windowStart = lastAlert.minusHours(2).toInstant().toEpochMilli(),
                windowEnd = lastAlert.plusHours(4).toInstant().toEpochMilli(),
                stepsReliable = true,
                targetReliable = true,
                currentSteps = 1000,
                stepGoal = 8000,
                currentMovements = 0,
                movementGoal = 3,
                baselineSteps = 1000,
                inactiveSince = lastAlert.minusHours(2).toInstant().toEpochMilli(),
                lastAlertAt = lastAlert.toInstant().toEpochMilli(),
            ),
        )

        assertEquals(SmartAlertPolicy.Action.DEFER, decision.action)
        assertEquals("cooldown", decision.deferReason)
        assertEquals(
            now.plus(SmartAlertPolicy.evaluationInterval).toInstant().toEpochMilli(),
            decision.nextCheckAt,
        )
    }

    @Test
    fun activeWindowEndIsExclusive() {
        val end = Duration.ofHours(12).toMillis()
        val decision = SmartAlertPolicy.evaluate(
            baseInput(now = end, baseline = 1000, inactiveSince = 0L),
        )

        assertEquals(SmartAlertPolicy.Action.OUTSIDE_WINDOW, decision.action)
    }

    @Test
    fun threeAlertsStopsForTheDay() {
        val decision = SmartAlertPolicy.evaluate(
            baseInput(
                now = Duration.ofHours(2).toMillis(),
                baseline = 1000,
                inactiveSince = 0L,
                alertsToday = 3,
            ),
        )

        assertEquals(SmartAlertPolicy.Action.DEFER, decision.action)
        assertEquals("daily_limit", decision.deferReason)
        assertNull(decision.nextCheckAt)
    }

    @Test
    fun visibleNotificationPreventsDuplicate() {
        val decision = SmartAlertPolicy.evaluate(
            baseInput(
                now = Duration.ofHours(1).toMillis(),
                baseline = 1000,
                inactiveSince = 0L,
                notificationVisible = true,
            ),
        )

        assertEquals(SmartAlertPolicy.Action.DEFER, decision.action)
        assertEquals("notification_visible", decision.deferReason)
    }

    @Test
    fun unreliableReadBreaksInactivityProofAndForcesRebaseline() {
        val decision = SmartAlertPolicy.evaluate(
            baseInput(
                now = Duration.ofHours(1).toMillis(),
                baseline = 1000,
                inactiveSince = 0L,
                stepsReliable = false,
            ),
        )

        assertEquals(SmartAlertPolicy.Action.DEFER, decision.action)
        assertNull(decision.baselineSteps)
        assertNull(decision.inactiveSince)
        assertEquals("unreliable_steps", decision.deferReason)
    }

    @Test
    fun unreliableTargetAlsoForcesRebaseline() {
        val decision = SmartAlertPolicy.evaluate(
            baseInput(
                now = Duration.ofHours(1).toMillis(),
                baseline = 1000,
                inactiveSince = 0L,
                targetReliable = false,
            ),
        )

        assertEquals(SmartAlertPolicy.Action.DEFER, decision.action)
        assertNull(decision.baselineSteps)
        assertEquals("unreliable_target", decision.deferReason)
    }

    @Test
    fun stepCounterDecreaseSafelyRebaselinesWithoutClaimingActivity() {
        val hour = Duration.ofHours(1).toMillis()
        val decision = SmartAlertPolicy.evaluate(
            baseInput(
                now = hour,
                baseline = 1200,
                inactiveSince = 0L,
                currentSteps = 1000,
            ),
        )

        assertEquals(SmartAlertPolicy.Action.DEFER, decision.action)
        assertEquals("step_counter_reset", decision.deferReason)
        assertEquals(1000, decision.baselineSteps)
        assertEquals(hour, decision.inactiveSince)
    }

    @Test
    fun dayZoneOffsetConfigurationAndClockRegressionResetState() {
        val today = LocalDate.of(2026, 8, 30)
        fun reset(
            date: String = today.toString(),
            storedZone: String = zone.id,
            offset: Int = 3600,
            configuration: String = "same",
            lastEvaluation: Long = 100L,
            now: Long = 100L,
        ) = SmartAlertPolicy.requiresStateReset(
            storedDate = date,
            currentDate = today,
            storedZone = storedZone,
            currentZone = zone,
            storedOffsetSeconds = offset,
            currentOffsetSeconds = 3600,
            storedConfiguration = configuration,
            currentConfiguration = "same",
            lastEvaluationAt = lastEvaluation,
            now = now,
        )

        assertFalse(reset())
        assertTrue(reset(date = today.minusDays(1).toString()))
        assertTrue(reset(storedZone = "UTC"))
        assertTrue(reset(offset = 0))
        assertTrue(reset(configuration = "changed"))
        assertTrue(reset(lastEvaluation = 101L, now = 100L))
    }

    @Test
    fun widgetKeepsYesterdayStreakButExpiresOlderSnapshots() {
        val today = LocalDate.of(2026, 8, 26)

        assertEquals(4, MoveStateStore.resolvedStreak(today.minusDays(1), 4, today))
        assertEquals(0, MoveStateStore.resolvedStreak(today.minusDays(2), 4, today))
    }

    @Test
    fun currentSnapshotUsesSamsungStepGoalAndOldSnapshotUsesFallback() {
        val today = LocalDate.of(2026, 8, 30)

        assertEquals(12000, MoveStateStore.resolvedStepGoal(today, 12000, 8000, true, today))
        assertEquals(
            8000,
            MoveStateStore.resolvedStepGoal(today.minusDays(1), 12000, 8000, true, today),
        )
        assertEquals(8000, MoveStateStore.resolvedStepGoal(today, 12000, 8000, false, today))
    }

    private fun baseInput(
        now: Long,
        baseline: Int?,
        inactiveSince: Long? = null,
        currentSteps: Int = 1000,
        movements: Int = 0,
        movementActivity: Boolean = false,
        lastAlertAt: Long? = null,
        alertsToday: Int = 0,
        notificationVisible: Boolean = false,
        stepsReliable: Boolean = true,
        targetReliable: Boolean = true,
    ) = SmartAlertPolicy.Input(
        now = now,
        windowStart = 0L,
        windowEnd = Duration.ofHours(12).toMillis(),
        stepsReliable = stepsReliable,
        targetReliable = targetReliable,
        currentSteps = currentSteps,
        stepGoal = 8000,
        currentMovements = movements,
        movementGoal = 3,
        baselineSteps = baseline,
        inactiveSince = inactiveSince,
        movementActivity = movementActivity,
        lastAlertAt = lastAlertAt,
        alertsToday = alertsToday,
        notificationVisible = notificationVisible,
    )
}
