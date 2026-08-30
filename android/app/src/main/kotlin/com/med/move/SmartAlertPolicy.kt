package com.med.move

import java.time.Duration
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZonedDateTime
import kotlin.math.ceil

internal object SmartAlertPolicy {
    const val FALLBACK_START_MINUTES = 8 * 60
    const val FALLBACK_END_MINUTES = 22 * 60
    const val MIN_STEP_THRESHOLD = 100
    const val MAX_STEP_THRESHOLD = 400

    val inactivityDuration: Duration = Duration.ofHours(1)
    val cooldownDuration: Duration = Duration.ofHours(2)
    val evaluationInterval: Duration = Duration.ofMinutes(15)
    val visibleNotificationRecheck: Duration = evaluationInterval

    data class ActiveWindow(
        val start: ZonedDateTime,
        val end: ZonedDateTime,
        val usesSamsungTarget: Boolean,
    ) {
        val earliestAlert: ZonedDateTime
            get() = start.plus(inactivityDuration)

        val isAlertable: Boolean
            get() = earliestAlert.isBefore(end)
    }

    enum class Action {
        OUTSIDE_WINDOW,
        GOALS_COMPLETE,
        DEFER,
        BASELINE,
        ACTIVITY,
        WAIT,
        ALERT,
    }

    data class Input(
        val now: Long,
        val windowStart: Long,
        val windowEnd: Long,
        val stepsReliable: Boolean,
        val targetReliable: Boolean,
        val currentSteps: Int,
        val stepGoal: Int,
        val currentMovements: Int,
        val movementGoal: Int,
        val baselineSteps: Int?,
        val inactiveSince: Long?,
        val movementActivity: Boolean = false,
        val lastAlertAt: Long? = null,
        val alertsToday: Int = 0,
        val notificationVisible: Boolean = false,
    )

    data class Decision(
        val action: Action,
        val baselineSteps: Int?,
        val inactiveSince: Long?,
        val nextCheckAt: Long?,
        val deferReason: String = "",
        val adaptiveThreshold: Int = 0,
    )

    fun activeWindow(
        date: LocalDate,
        zone: ZoneId,
        wakeMinutes: Int?,
        bedtimeMinutes: Int?,
    ): ActiveWindow {
        val samsungWindow = if (
            wakeMinutes in 0 until 24 * 60 &&
            bedtimeMinutes in 0 until 24 * 60 &&
            wakeMinutes != bedtimeMinutes
        ) {
            val wake = date.atTime(wakeMinutes!! / 60, wakeMinutes % 60).atZone(zone)
            var bedtime = date.atTime(
                bedtimeMinutes!! / 60,
                bedtimeMinutes % 60,
            ).atZone(zone)
            if (!bedtime.isAfter(wake)) bedtime = bedtime.plusDays(1)
            ActiveWindow(
                start = wake.plusHours(1),
                end = bedtime.minusHours(1),
                usesSamsungTarget = true,
            )
        } else {
            null
        }
        return samsungWindow ?: ActiveWindow(
            start = date.atTime(8, 0).atZone(zone),
            end = date.atTime(22, 0).atZone(zone),
            usesSamsungTarget = false,
        )
    }

    fun activeWindowForMoment(
        now: ZonedDateTime,
        wakeMinutes: Int?,
        bedtimeMinutes: Int?,
    ): ActiveWindow {
        val today = activeWindow(now.toLocalDate(), now.zone, wakeMinutes, bedtimeMinutes)
        if (!now.isBefore(today.start)) return today
        val previous = activeWindow(
            now.toLocalDate().minusDays(1),
            now.zone,
            wakeMinutes,
            bedtimeMinutes,
        )
        return if (!now.isBefore(previous.start) && now.isBefore(previous.end)) {
            previous
        } else {
            today
        }
    }

    fun adaptiveStepThreshold(
        currentSteps: Int,
        stepGoal: Int,
        now: Long,
        windowEnd: Long,
    ): Int {
        val remainingSteps = (stepGoal - currentSteps).coerceAtLeast(0)
        val remainingMillis = (windowEnd - now).coerceAtLeast(1L)
        val remainingHours = remainingMillis.toDouble() / Duration.ofHours(1).toMillis()
        return ceil(0.25 * remainingSteps / remainingHours)
            .toInt()
            .coerceIn(MIN_STEP_THRESHOLD, MAX_STEP_THRESHOLD)
    }

    fun evaluate(input: Input): Decision {
        if (input.now < input.windowStart || input.now >= input.windowEnd) {
            return Decision(
                action = Action.OUTSIDE_WINDOW,
                baselineSteps = input.baselineSteps,
                inactiveSince = input.inactiveSince,
                nextCheckAt = if (input.now < input.windowStart) input.windowStart else null,
                deferReason = "outside_active_window",
            )
        }

        if (input.movementActivity) {
            return Decision(
                action = Action.ACTIVITY,
                baselineSteps = input.currentSteps.takeIf { input.stepsReliable },
                inactiveSince = input.now,
                nextCheckAt = input.now + evaluationInterval.toMillis(),
                deferReason = "activity_detected",
            )
        }

        if (!input.stepsReliable) {
            return Decision(
                action = Action.DEFER,
                baselineSteps = null,
                inactiveSince = null,
                nextCheckAt = input.now + visibleNotificationRecheck.toMillis(),
                deferReason = "unreliable_steps",
            )
        }
        if (!input.targetReliable) {
            return Decision(
                action = Action.DEFER,
                baselineSteps = null,
                inactiveSince = null,
                nextCheckAt = input.now + visibleNotificationRecheck.toMillis(),
                deferReason = "unreliable_target",
            )
        }

        if (
            input.currentSteps >= input.stepGoal &&
            input.currentMovements >= input.movementGoal
        ) {
            return Decision(
                action = Action.GOALS_COMPLETE,
                baselineSteps = input.currentSteps,
                inactiveSince = null,
                nextCheckAt = null,
                deferReason = "goals_complete",
            )
        }

        val baseline = input.baselineSteps
        if (baseline == null) {
            val inactiveSince = input.inactiveSince
                ?.coerceIn(input.windowStart, input.now)
                ?: input.now.coerceAtLeast(input.windowStart)
            return Decision(
                action = Action.BASELINE,
                baselineSteps = input.currentSteps,
                inactiveSince = inactiveSince,
                nextCheckAt = minOf(
                    inactiveSince + inactivityDuration.toMillis(),
                    input.now + evaluationInterval.toMillis(),
                ),
                deferReason = "awaiting_baseline",
            )
        }

        if (input.currentSteps < baseline) {
            return Decision(
                action = Action.DEFER,
                baselineSteps = input.currentSteps,
                inactiveSince = input.now,
                nextCheckAt = input.now + evaluationInterval.toMillis(),
                deferReason = "step_counter_reset",
            )
        }

        val threshold = adaptiveStepThreshold(
            currentSteps = input.currentSteps,
            stepGoal = input.stepGoal,
            now = input.now,
            windowEnd = input.windowEnd,
        )
        if (input.currentSteps - baseline >= threshold && threshold > 0) {
            return Decision(
                action = Action.ACTIVITY,
                baselineSteps = input.currentSteps,
                inactiveSince = input.now,
                nextCheckAt = input.now + evaluationInterval.toMillis(),
                deferReason = "activity_detected",
                adaptiveThreshold = threshold,
            )
        }

        val inactiveSince = input.inactiveSince
            ?.coerceIn(input.windowStart, input.now)
            ?: input.now.coerceAtLeast(input.windowStart)
        val eligibleAt = inactiveSince + inactivityDuration.toMillis()
        if (input.now < eligibleAt) {
            return Decision(
                action = Action.WAIT,
                baselineSteps = baseline,
                inactiveSince = inactiveSince,
                nextCheckAt = minOf(
                    eligibleAt,
                    input.now + evaluationInterval.toMillis(),
                ),
                adaptiveThreshold = threshold,
            )
        }

        if (input.alertsToday >= 3) {
            return Decision(
                action = Action.DEFER,
                baselineSteps = baseline,
                inactiveSince = inactiveSince,
                nextCheckAt = null,
                deferReason = "daily_limit",
                adaptiveThreshold = threshold,
            )
        }

        val cooldownEnds = input.lastAlertAt?.plus(cooldownDuration.toMillis())
        if (cooldownEnds != null && input.now < cooldownEnds) {
            return Decision(
                action = Action.DEFER,
                baselineSteps = baseline,
                inactiveSince = inactiveSince,
                nextCheckAt = minOf(
                    cooldownEnds,
                    input.now + evaluationInterval.toMillis(),
                ),
                deferReason = "cooldown",
                adaptiveThreshold = threshold,
            )
        }

        if (input.notificationVisible) {
            return Decision(
                action = Action.DEFER,
                baselineSteps = baseline,
                inactiveSince = inactiveSince,
                nextCheckAt = input.now + visibleNotificationRecheck.toMillis(),
                deferReason = "notification_visible",
                adaptiveThreshold = threshold,
            )
        }

        return Decision(
            action = Action.ALERT,
            baselineSteps = baseline,
            inactiveSince = inactiveSince,
            nextCheckAt = input.now + evaluationInterval.toMillis(),
            adaptiveThreshold = threshold,
        )
    }

    fun requiresStateReset(
        storedDate: String?,
        currentDate: LocalDate,
        storedZone: String?,
        currentZone: ZoneId,
        storedOffsetSeconds: Int?,
        currentOffsetSeconds: Int,
        storedConfiguration: String?,
        currentConfiguration: String,
        lastEvaluationAt: Long,
        now: Long,
    ): Boolean = storedDate != currentDate.toString() ||
        storedZone != currentZone.id ||
        storedOffsetSeconds != currentOffsetSeconds ||
        storedConfiguration != currentConfiguration ||
        (lastEvaluationAt > 0L && now < lastEvaluationAt)
}
