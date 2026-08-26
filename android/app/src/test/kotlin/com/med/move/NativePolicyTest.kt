package com.med.move

import java.time.LocalDate
import java.time.ZoneId
import java.time.ZonedDateTime
import org.junit.Assert.assertEquals
import org.junit.Test

class NativePolicyTest {
    private val zone = ZoneId.of("Africa/Casablanca")

    @Test
    fun reminderAlreadyHandledTodaySchedulesTomorrow() {
        val now = ZonedDateTime.of(2026, 8, 26, 12, 0, 0, 0, zone)

        assertEquals(
            LocalDate.of(2026, 8, 27),
            ReminderScheduler.nextScheduleDate(now, LocalDate.of(2026, 8, 26)),
        )
    }

    @Test
    fun unhandledReminderUsesTodayInsideTheWindow() {
        val now = ZonedDateTime.of(2026, 8, 26, 12, 0, 0, 0, zone)

        assertEquals(
            LocalDate.of(2026, 8, 26),
            ReminderScheduler.nextScheduleDate(now, null),
        )
    }

    @Test
    fun unhandledReminderWaitsUntilTomorrowNearDayEnd() {
        val now = ZonedDateTime.of(2026, 8, 26, 22, 50, 0, 0, zone)

        assertEquals(
            LocalDate.of(2026, 8, 27),
            ReminderScheduler.nextScheduleDate(now, null),
        )
    }

    @Test
    fun widgetKeepsYesterdayStreakButExpiresOlderSnapshots() {
        val today = LocalDate.of(2026, 8, 26)

        assertEquals(
            4,
            MoveStateStore.resolvedStreak(today.minusDays(1), 4, today),
        )
        assertEquals(
            0,
            MoveStateStore.resolvedStreak(today.minusDays(2), 4, today),
        )
    }
}
