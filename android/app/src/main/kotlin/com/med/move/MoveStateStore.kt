package com.med.move

import android.content.Context
import java.time.LocalDate

object MoveStateStore {
    private const val PREFS = "move_shared_state"
    private const val KEY_STEP_GOAL = "step_goal"
    private const val KEY_MOVEMENT_GOAL = "movement_goal"
    private const val KEY_QUICK_IDS = "quick_movement_ids"
    private const val KEY_BEDTIME_START_MINUTES = "bedtime_start_minutes"
    private const val KEY_BEDTIME_END_MINUTES = "bedtime_end_minutes"
    private const val KEY_WAKE_START_MINUTES = "wake_start_minutes"
    private const val KEY_WAKE_END_MINUTES = "wake_end_minutes"
    private const val KEY_SNAPSHOT_DATE = "snapshot_date"
    private const val KEY_TODAY_STEPS = "today_steps"
    private const val KEY_TODAY_MOVEMENTS = "today_movements"
    private const val KEY_STREAK = "current_streak"
    private const val KEY_LAST_UPDATED = "last_updated"
    private const val QUICK_ID_SEPARATOR = "\u001F"

    const val DEFAULT_STEP_GOAL = 8000
    const val DEFAULT_MOVEMENT_GOAL = 3
    const val DEFAULT_BEDTIME_START_MINUTES = 23 * 60
    const val DEFAULT_BEDTIME_END_MINUTES = 0
    const val DEFAULT_WAKE_START_MINUTES = 7 * 60
    const val DEFAULT_WAKE_END_MINUTES = 8 * 60

    private val defaultQuickIds = listOf(
        "squat",
        "push_up",
        "hand_grip",
        "plank",
        "shoulder_stretch",
        "hip_flexor_stretch",
    )

    data class Snapshot(
        val isCurrentDay: Boolean,
        val steps: Int,
        val movements: Int,
        val streak: Int,
        val stepGoal: Int,
        val movementGoal: Int,
        val lastUpdated: Long,
    ) {
        val goalsComplete: Boolean
            get() = steps >= stepGoal && movements >= movementGoal
    }

    fun preferencesMap(context: Context): Map<String, Any> {
        val prefs = preferences(context)
        return mapOf(
            "stepGoal" to prefs.getInt(KEY_STEP_GOAL, DEFAULT_STEP_GOAL),
            "movementGoal" to prefs.getInt(KEY_MOVEMENT_GOAL, DEFAULT_MOVEMENT_GOAL),
            "quickMovementIds" to quickMovementIds(context),
            "bedtimeStartMinutes" to prefs.getInt(
                KEY_BEDTIME_START_MINUTES,
                DEFAULT_BEDTIME_START_MINUTES,
            ),
            "bedtimeEndMinutes" to prefs.getInt(
                KEY_BEDTIME_END_MINUTES,
                DEFAULT_BEDTIME_END_MINUTES,
            ),
            "wakeStartMinutes" to prefs.getInt(
                KEY_WAKE_START_MINUTES,
                DEFAULT_WAKE_START_MINUTES,
            ),
            "wakeEndMinutes" to prefs.getInt(
                KEY_WAKE_END_MINUTES,
                DEFAULT_WAKE_END_MINUTES,
            ),
        )
    }

    fun setGoals(context: Context, stepGoal: Int, movementGoal: Int): Map<String, Any> {
        preferences(context).edit()
            .putInt(KEY_STEP_GOAL, stepGoal.coerceIn(1000, 30000))
            .putInt(KEY_MOVEMENT_GOAL, movementGoal.coerceIn(1, 10))
            .apply()
        MoveWidgetProvider.updateAll(context)
        return preferencesMap(context)
    }

    fun setQuickMovementIds(context: Context, ids: List<String>) {
        val clean = ids.distinct().take(8)
        if (clean.size < 2) return
        preferences(context).edit()
            .putString(KEY_QUICK_IDS, clean.joinToString(QUICK_ID_SEPARATOR))
            .apply()
    }

    fun setSleepSchedule(
        context: Context,
        bedtimeStartMinutes: Int,
        bedtimeEndMinutes: Int,
        wakeStartMinutes: Int,
        wakeEndMinutes: Int,
    ): Map<String, Any> {
        preferences(context).edit()
            .putInt(KEY_BEDTIME_START_MINUTES, bedtimeStartMinutes.coerceIn(0, 1439))
            .putInt(KEY_BEDTIME_END_MINUTES, bedtimeEndMinutes.coerceIn(0, 1439))
            .putInt(KEY_WAKE_START_MINUTES, wakeStartMinutes.coerceIn(0, 1439))
            .putInt(KEY_WAKE_END_MINUTES, wakeEndMinutes.coerceIn(0, 1439))
            .apply()
        return preferencesMap(context)
    }

    fun updateSnapshot(
        context: Context,
        date: String,
        steps: Int,
        movements: Int,
        streak: Int,
    ) {
        preferences(context).edit()
            .putString(KEY_SNAPSHOT_DATE, date)
            .putInt(KEY_TODAY_STEPS, steps.coerceAtLeast(0))
            .putInt(KEY_TODAY_MOVEMENTS, movements.coerceAtLeast(0))
            .putInt(KEY_STREAK, streak.coerceAtLeast(0))
            .putLong(KEY_LAST_UPDATED, System.currentTimeMillis())
            .apply()
        MoveWidgetProvider.updateAll(context)
    }

    fun snapshot(context: Context): Snapshot {
        val prefs = preferences(context)
        val today = LocalDate.now()
        val snapshotDate = prefs.getString(KEY_SNAPSHOT_DATE, null)?.let { stored ->
            runCatching { LocalDate.parse(stored) }.getOrNull()
        }
        val isCurrentDay = snapshotDate == today
        return Snapshot(
            isCurrentDay = isCurrentDay,
            steps = if (isCurrentDay) prefs.getInt(KEY_TODAY_STEPS, 0) else 0,
            movements = if (isCurrentDay) prefs.getInt(KEY_TODAY_MOVEMENTS, 0) else 0,
            streak = resolvedStreak(
                snapshotDate = snapshotDate,
                storedStreak = prefs.getInt(KEY_STREAK, 0),
                today = today,
            ),
            stepGoal = prefs.getInt(KEY_STEP_GOAL, DEFAULT_STEP_GOAL),
            movementGoal = prefs.getInt(KEY_MOVEMENT_GOAL, DEFAULT_MOVEMENT_GOAL),
            lastUpdated = prefs.getLong(KEY_LAST_UPDATED, 0L),
        )
    }

    internal fun resolvedStreak(
        snapshotDate: LocalDate?,
        storedStreak: Int,
        today: LocalDate,
    ): Int {
        val canStillBeCurrent = snapshotDate == today || snapshotDate == today.minusDays(1)
        return if (canStillBeCurrent) storedStreak.coerceAtLeast(0) else 0
    }

    private fun quickMovementIds(context: Context): List<String> {
        val stored = preferences(context).getString(KEY_QUICK_IDS, null) ?: return defaultQuickIds
        val ids = stored.split(QUICK_ID_SEPARATOR).filter(String::isNotBlank).distinct().take(8)
        return if (ids.size >= 2) ids else defaultQuickIds
    }

    private fun preferences(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}
