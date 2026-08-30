package com.med.move

import android.content.Context
import java.time.LocalDate

object MoveStateStore {
    private const val PREFS = "move_shared_state"
    private const val KEY_STEP_GOAL = "step_goal"
    private const val KEY_MOVEMENT_GOAL = "movement_goal"
    private const val KEY_QUICK_IDS = "quick_movement_ids"
    private const val KEY_SNAPSHOT_DATE = "snapshot_date"
    private const val KEY_TODAY_STEPS = "today_steps"
    private const val KEY_TODAY_MOVEMENTS = "today_movements"
    private const val KEY_STREAK = "current_streak"
    private const val KEY_LAST_UPDATED = "last_updated"
    private const val KEY_SNAPSHOT_STEP_GOAL = "snapshot_step_goal"
    private const val KEY_SNAPSHOT_USES_SAMSUNG_STEP_GOAL =
        "snapshot_uses_samsung_step_goal"
    private const val QUICK_ID_SEPARATOR = "\u001F"

    const val DEFAULT_STEP_GOAL = 8000
    const val DEFAULT_MOVEMENT_GOAL = 3

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
        val values = mutableMapOf<String, Any>(
            "stepGoal" to prefs.getInt(KEY_STEP_GOAL, DEFAULT_STEP_GOAL),
            "movementGoal" to prefs.getInt(KEY_MOVEMENT_GOAL, DEFAULT_MOVEMENT_GOAL),
            "quickMovementIds" to quickMovementIds(context),
        )
        cachedSamsungStepGoal(prefs)?.let {
            values["cachedSamsungStepGoal"] = it
            values["cachedSamsungStepGoalDate"] = LocalDate.now().toString()
        }
        return values
    }

    fun setGoals(context: Context, stepGoal: Int, movementGoal: Int): Map<String, Any> {
        val prefs = preferences(context)
        val safeStepGoal = stepGoal.coerceIn(1000, 30000)
        val editor = prefs.edit()
            .putInt(KEY_STEP_GOAL, safeStepGoal)
            .putInt(KEY_MOVEMENT_GOAL, movementGoal.coerceIn(1, 10))
        if (!prefs.getBoolean(KEY_SNAPSHOT_USES_SAMSUNG_STEP_GOAL, false)) {
            editor.putInt(KEY_SNAPSHOT_STEP_GOAL, safeStepGoal)
        }
        editor.apply()
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

    fun updateSnapshot(
        context: Context,
        date: String,
        steps: Int,
        movements: Int,
        streak: Int,
        stepGoal: Int,
        usesSamsungStepGoal: Boolean,
    ) {
        preferences(context).edit()
            .putString(KEY_SNAPSHOT_DATE, date)
            .putInt(KEY_TODAY_STEPS, steps.coerceAtLeast(0))
            .putInt(KEY_TODAY_MOVEMENTS, movements.coerceAtLeast(0))
            .putInt(KEY_STREAK, streak.coerceAtLeast(0))
            .putInt(KEY_SNAPSHOT_STEP_GOAL, stepGoal.coerceIn(1, 1_000_000))
            .putBoolean(KEY_SNAPSHOT_USES_SAMSUNG_STEP_GOAL, usesSamsungStepGoal)
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
            stepGoal = resolvedStepGoal(
                snapshotDate = snapshotDate,
                snapshotStepGoal = prefs.getInt(
                    KEY_SNAPSHOT_STEP_GOAL,
                    prefs.getInt(KEY_STEP_GOAL, DEFAULT_STEP_GOAL),
                ),
                fallbackStepGoal = prefs.getInt(KEY_STEP_GOAL, DEFAULT_STEP_GOAL),
                usesSamsungStepGoal = prefs.getBoolean(
                    KEY_SNAPSHOT_USES_SAMSUNG_STEP_GOAL,
                    false,
                ),
                today = today,
            ),
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

    internal fun resolvedStepGoal(
        snapshotDate: LocalDate?,
        snapshotStepGoal: Int,
        fallbackStepGoal: Int,
        usesSamsungStepGoal: Boolean,
        today: LocalDate,
    ): Int = if (snapshotDate == today && usesSamsungStepGoal) {
        snapshotStepGoal.coerceIn(1, 1_000_000)
    } else {
        fallbackStepGoal.coerceIn(1000, 30000)
    }

    private fun cachedSamsungStepGoal(
        preferences: android.content.SharedPreferences,
        today: LocalDate = LocalDate.now(),
    ): Int? {
        val snapshotDate = preferences.getString(KEY_SNAPSHOT_DATE, null)?.let { stored ->
            runCatching { LocalDate.parse(stored) }.getOrNull()
        }
        if (snapshotDate != today ||
            !preferences.getBoolean(KEY_SNAPSHOT_USES_SAMSUNG_STEP_GOAL, false)
        ) {
            return null
        }
        return preferences.getInt(KEY_SNAPSHOT_STEP_GOAL, 0)
            .takeIf { it in 1..1_000_000 }
    }

    private fun quickMovementIds(context: Context): List<String> {
        val stored = preferences(context).getString(KEY_QUICK_IDS, null) ?: return defaultQuickIds
        val ids = stored.split(QUICK_ID_SEPARATOR).filter(String::isNotBlank).distinct().take(8)
        return if (ids.size >= 2) ids else defaultQuickIds
    }

    private fun preferences(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}
