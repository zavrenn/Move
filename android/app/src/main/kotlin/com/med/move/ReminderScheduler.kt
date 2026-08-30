package com.med.move

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.work.BackoffPolicy
import androidx.work.CoroutineWorker
import androidx.work.Data
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.concurrent.TimeUnit

object ReminderScheduler {
    private const val PREFS = "move_reminders"
    private const val KEY_ENABLED = "enabled"
    private const val KEY_SCHEMA = "smart_schema"
    private const val KEY_GENERATION = "smart_generation"
    private const val KEY_WORK_NAME = "smart_work_name"
    private const val KEY_NEXT_AT = "next_at"
    private const val KEY_STATE_DATE = "smart_state_date"
    private const val KEY_STATE_ZONE = "smart_state_zone"
    private const val KEY_STATE_OFFSET = "smart_state_offset"
    private const val KEY_CONFIGURATION = "smart_configuration"
    private const val KEY_BASELINE_STEPS = "smart_baseline_steps"
    private const val KEY_LAST_OBSERVED_STEPS = "smart_last_observed_steps"
    private const val KEY_OBSERVED_MOVEMENTS = "smart_observed_movements"
    private const val KEY_INACTIVE_SINCE = "smart_inactive_since"
    private const val KEY_LAST_ACTIVITY_AT = "smart_last_activity_at"
    private const val KEY_LAST_MOVEMENT_EVENT_AT = "smart_last_movement_event_at"
    private const val KEY_LAST_ALERT_AT = "smart_last_alert_at"
    private const val KEY_ALERTS_TODAY = "smart_alerts_today"
    private const val KEY_TRACKING_START_AT = "smart_tracking_start_at"
    private const val KEY_WINDOW_END_AT = "smart_window_end_at"
    private const val KEY_LAST_EVALUATION_AT = "smart_last_evaluation_at"
    private const val KEY_DEFER_REASON = "smart_defer_reason"
    private const val KEY_ADAPTIVE_THRESHOLD = "smart_adaptive_threshold"
    private const val KEY_LEGACY_LAST_REMINDER_DATE = "last_reminder_date"

    private const val SMART_SCHEMA = 3
    private const val CHANNEL_ID = "move_daily_reminder"
    private const val LEGACY_ALARM_REQUEST_CODE = 7021
    private const val NOTIFICATION_ID = 7022
    private const val WORK_TAG = "move-smart-alert-check"
    private const val INPUT_GENERATION = "generation"
    private const val PERMISSION_RECHECK_MILLIS = 60L * 60L * 1000L
    private val stateLock = Any()

    fun initialize(context: Context) {
        ensureNotificationChannel(context)
        cancelLegacyAlarm(context)
        synchronized(stateLock) {
            val prefs = preferences(context)
            if (prefs.getInt(KEY_SCHEMA, 0) < SMART_SCHEMA) {
                val generation = prefs.getLong(KEY_GENERATION, 0L) + 1L
                val legacyAlertWasToday = prefs.getString(KEY_LEGACY_LAST_REMINDER_DATE, null)
                    ?.let { runCatching { LocalDate.parse(it) }.getOrNull() }
                    ?.let { it == LocalDate.now(ZoneId.systemDefault()) } == true
                val migrationEditor = prefs.edit()
                    .putInt(KEY_SCHEMA, SMART_SCHEMA)
                    .putLong(KEY_GENERATION, generation)
                    .remove(KEY_LEGACY_LAST_REMINDER_DATE)
                    .putLong(KEY_NEXT_AT, 0L)
                    .putInt(KEY_BASELINE_STEPS, -1)
                    .putLong(KEY_INACTIVE_SINCE, 0L)
                    .putString(KEY_DEFER_REASON, "awaiting_baseline")
                if (legacyAlertWasToday) {
                    migrationEditor.putInt(
                        KEY_ALERTS_TODAY,
                        maxOf(1, prefs.getInt(KEY_ALERTS_TODAY, 0)),
                    ).putString(
                        KEY_STATE_DATE,
                        LocalDate.now(ZoneId.systemDefault()).toString(),
                    )
                }
                migrationEditor.apply()
                prefs.getString(KEY_WORK_NAME, null)?.let {
                    WorkManager.getInstance(context).cancelUniqueWork(it)
                }
            }
            ensureScheduled(context)
        }
    }

    fun setEnabled(context: Context, enabled: Boolean) {
        synchronized(stateLock) {
            preferences(context).edit().putBoolean(KEY_ENABLED, enabled).apply()
            if (enabled) {
                resetAndSchedule(context, System.currentTimeMillis(), "awaiting_baseline")
            } else {
                cancelNotification(context)
                stopAndInvalidate(context, "disabled")
            }
        }
    }

    fun isEnabled(context: Context): Boolean =
        preferences(context).getBoolean(KEY_ENABLED, false)

    suspend fun status(context: Context): Map<String, Any> {
        val capabilities = SmartAlertDataSource(context).capabilities()
        val notificationGranted = notificationsAllowed(context)
        return synchronized(stateLock) {
            val prefs = preferences(context)
            val enabled = prefs.getBoolean(KEY_ENABLED, false)
            val permissionReason = when {
                !enabled -> "disabled"
                !notificationGranted -> "notification_permission_required"
                !capabilities.stepsGranted -> "steps_permission_required"
                !capabilities.backgroundReadAvailable -> "background_read_unavailable"
                !capabilities.backgroundReadGranted -> "background_read_permission_required"
                else -> null
            }
            val now = System.currentTimeMillis()
            val trackingStart = prefs.getLong(KEY_TRACKING_START_AT, 0L)
            val windowEnd = prefs.getLong(KEY_WINDOW_END_AT, 0L)
            val operational = enabled && permissionReason == null
            val nextAt = prefs.getLong(KEY_NEXT_AT, 0L)
            mapOf(
                "enabled" to enabled,
                "notificationGranted" to notificationGranted,
                "stepsGranted" to capabilities.stepsGranted,
                "backgroundReadAvailable" to capabilities.backgroundReadAvailable,
                "backgroundReadGranted" to capabilities.backgroundReadGranted,
                "operational" to operational,
                "workerScheduled" to (enabled && nextAt > 0L),
                "active" to (
                    operational && trackingStart > 0L && now >= trackingStart && now < windowEnd
                ),
                "trackingStartAt" to trackingStart,
                "activeWindowEndAt" to windowEnd,
                "inactiveSince" to prefs.getLong(KEY_INACTIVE_SINCE, 0L),
                "lastActivityAt" to prefs.getLong(KEY_LAST_ACTIVITY_AT, 0L),
                "lastAlertAt" to prefs.getLong(KEY_LAST_ALERT_AT, 0L),
                "alertsToday" to prefs.getInt(KEY_ALERTS_TODAY, 0),
                "nextCheckAt" to nextAt,
                "deferReason" to (
                    permissionReason ?: prefs.getString(KEY_DEFER_REASON, "").orEmpty()
                ),
                "adaptiveStepThreshold" to prefs.getInt(KEY_ADAPTIVE_THRESHOLD, 0),
            )
        }
    }

    fun ensureScheduled(context: Context) {
        synchronized(stateLock) {
            val prefs = preferences(context)
            if (!prefs.getBoolean(KEY_ENABLED, false)) return
            val nextAt = prefs.getLong(KEY_NEXT_AT, 0L)
            if (nextAt <= System.currentTimeMillis()) {
                resetAndSchedule(context, System.currentTimeMillis(), "awaiting_baseline")
            }
        }
    }

    fun restore(context: Context) {
        cancelLegacyAlarm(context)
        synchronized(stateLock) {
            cancelNotification(context)
            if (isEnabled(context)) {
                resetAndSchedule(context, System.currentTimeMillis(), "awaiting_baseline")
            } else {
                stopAndInvalidate(context, "disabled")
            }
        }
    }

    fun onConfigurationChanged(context: Context) {
        synchronized(stateLock) {
            if (!isEnabled(context)) return
            cancelNotification(context)
            resetAndSchedule(context, System.currentTimeMillis(), "awaiting_baseline")
        }
    }

    fun onSnapshotChanged(context: Context) {
        synchronized(stateLock) {
            if (!isEnabled(context)) return
            scheduleFresh(context, System.currentTimeMillis(), resetTracking = false)
        }
    }

    fun recordMovementActivity(context: Context, createdAt: Long): Boolean {
        synchronized(stateLock) {
            if (!isEnabled(context)) return false
            val prefs = preferences(context)
            val normalizedEvent = createdAt.takeIf { it > 0L } ?: System.currentTimeMillis()
            val now = System.currentTimeMillis()
            prefs.edit()
                .putLong(KEY_LAST_MOVEMENT_EVENT_AT, normalizedEvent)
                .putLong(KEY_LAST_ACTIVITY_AT, now)
                .putLong(KEY_INACTIVE_SINCE, now)
                .putInt(KEY_BASELINE_STEPS, -1)
                .putString(KEY_DEFER_REASON, "activity_detected")
                .putInt(KEY_ADAPTIVE_THRESHOLD, 0)
                .apply()
            cancelNotification(context)
            scheduleFresh(context, now, resetTracking = false)
            return true
        }
    }

    fun notificationsAllowed(context: Context): Boolean {
        val runtimeGranted = Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        if (!runtimeGranted ||
            !NotificationManagerCompat.from(context).areNotificationsEnabled()
        ) return false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = context.getSystemService(NotificationManager::class.java)
                .getNotificationChannel(CHANNEL_ID)
            if (channel?.importance == NotificationManager.IMPORTANCE_NONE) return false
        }
        return true
    }

    fun ensureNotificationChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Smart movement alerts",
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            description = "Adaptive reminders after a quiet hour"
            enableVibration(true)
        }
        context.getSystemService(NotificationManager::class.java)
            .createNotificationChannel(channel)
    }

    internal fun notificationVisible(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return false
        return runCatching {
            context.getSystemService(NotificationManager::class.java)
                .activeNotifications
                .any { it.id == NOTIFICATION_ID }
        }.getOrDefault(false)
    }

    private fun showNotification(
        context: Context,
        reading: SmartAlertDataSource.Reading,
    ): Boolean {
        if (!notificationsAllowed(context) || notificationVisible(context)) return false
        ensureNotificationChannel(context)
        val movementComplete = reading.movements >= reading.movementGoal
        val stepsComplete = reading.steps >= reading.stepGoal
        val copy = when {
            movementComplete && !stepsComplete ->
                "A short walk would help" to
                    "You’re ${reading.stepGoal - reading.steps} steps from today’s goal."
            stepsComplete && !movementComplete ->
                "Add one movement break" to
                    "Your steps are done—one quick set keeps your rhythm balanced."
            else ->
                "You’ve been still for a while" to
                    "A short walk or movement break can restart your rhythm."
        }
        val openApp = PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_move)
            .setContentTitle(copy.first)
            .setContentText(copy.second)
            .setStyle(NotificationCompat.BigTextStyle().bigText(copy.second))
            .setContentIntent(openApp)
            .setAutoCancel(true)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .build()
        context.getSystemService(NotificationManager::class.java)
            .notify(NOTIFICATION_ID, notification)
        return true
    }

    private fun cancelNotification(context: Context) {
        context.getSystemService(NotificationManager::class.java).cancel(NOTIFICATION_ID)
    }

    private fun stopAndInvalidate(context: Context, reason: String) {
        synchronized(stateLock) {
            val prefs = preferences(context)
            val generation = prefs.getLong(KEY_GENERATION, 0L) + 1L
            val workName = prefs.getString(KEY_WORK_NAME, null)
            prefs.edit()
                .putLong(KEY_GENERATION, generation)
                .putLong(KEY_NEXT_AT, 0L)
                .remove(KEY_WORK_NAME)
                .putString(KEY_DEFER_REASON, reason)
                .apply()
            workName?.let { WorkManager.getInstance(context).cancelUniqueWork(it) }
        }
    }

    private fun resetAndSchedule(context: Context, dueAt: Long, reason: String) {
        synchronized(stateLock) {
            preferences(context).edit()
                .putInt(KEY_BASELINE_STEPS, -1)
                .putInt(KEY_LAST_OBSERVED_STEPS, -1)
                .putInt(KEY_OBSERVED_MOVEMENTS, -1)
                .putLong(KEY_INACTIVE_SINCE, 0L)
                .putLong(KEY_TRACKING_START_AT, 0L)
                .putLong(KEY_WINDOW_END_AT, 0L)
                .putLong(KEY_LAST_EVALUATION_AT, 0L)
                .putLong(KEY_LAST_MOVEMENT_EVENT_AT, 0L)
                .putString(KEY_CONFIGURATION, "")
                .putString(KEY_DEFER_REASON, reason)
                .putInt(KEY_ADAPTIVE_THRESHOLD, 0)
                .apply()
            scheduleFresh(context, dueAt, resetTracking = false)
        }
    }

    private fun scheduleFresh(context: Context, dueAt: Long, resetTracking: Boolean) {
        synchronized(stateLock) {
            val prefs = preferences(context)
            if (!prefs.getBoolean(KEY_ENABLED, false)) return
            val generation = prefs.getLong(KEY_GENERATION, 0L) + 1L
            val previousWorkName = prefs.getString(KEY_WORK_NAME, null)
            val workName = workName(generation, dueAt)
            val editor = prefs.edit()
                .putLong(KEY_GENERATION, generation)
                .putLong(KEY_NEXT_AT, dueAt)
                .putString(KEY_WORK_NAME, workName)
            if (resetTracking) {
                editor.putInt(KEY_BASELINE_STEPS, -1).putLong(KEY_INACTIVE_SINCE, 0L)
            }
            editor.apply()
            previousWorkName?.takeIf { it != workName }?.let {
                WorkManager.getInstance(context).cancelUniqueWork(it)
            }
            enqueue(context, generation, dueAt, workName)
        }
    }

    private fun enqueueSuccessor(context: Context, generation: Long, dueAt: Long?) {
        synchronized(stateLock) {
            val prefs = preferences(context)
            if (!isCurrentGeneration(prefs, generation)) return
            if (dueAt == null) {
                prefs.edit().putLong(KEY_NEXT_AT, 0L).remove(KEY_WORK_NAME).apply()
                return
            }
            val workName = workName(generation, dueAt)
            prefs.edit()
                .putLong(KEY_NEXT_AT, dueAt)
                .putString(KEY_WORK_NAME, workName)
                .apply()
            enqueue(context, generation, dueAt, workName)
        }
    }

    private fun enqueue(
        context: Context,
        generation: Long,
        dueAt: Long,
        workName: String,
    ) {
        val delay = (dueAt - System.currentTimeMillis()).coerceAtLeast(0L)
        val request = OneTimeWorkRequestBuilder<SmartMovementAlertWorker>()
            .setInitialDelay(delay, TimeUnit.MILLISECONDS)
            .setBackoffCriteria(BackoffPolicy.LINEAR, 15L, TimeUnit.MINUTES)
            .setInputData(Data.Builder().putLong(INPUT_GENERATION, generation).build())
            .addTag(WORK_TAG)
            .build()
        WorkManager.getInstance(context).enqueueUniqueWork(
            workName,
            ExistingWorkPolicy.REPLACE,
            request,
        )
    }

    private fun workName(generation: Long, dueAt: Long) =
        "move-smart-alert-$generation-$dueAt"

    private fun cancelLegacyAlarm(context: Context) {
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            LEGACY_ALARM_REQUEST_CODE,
            Intent(context, MoveReminderReceiver::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        context.getSystemService(AlarmManager::class.java).cancel(pendingIntent)
        pendingIntent.cancel()
    }

    private fun preferences(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun isCurrentGeneration(
        prefs: android.content.SharedPreferences,
        generation: Long,
    ): Boolean = prefs.getBoolean(KEY_ENABLED, false) &&
        prefs.getLong(KEY_GENERATION, -1L) == generation

    private inline fun mutateIfCurrent(
        prefs: android.content.SharedPreferences,
        generation: Long,
        mutation: () -> Unit,
    ): Boolean = synchronized(stateLock) {
        if (!isCurrentGeneration(prefs, generation)) return@synchronized false
        mutation()
        true
    }

    internal suspend fun runCheck(context: Context, generation: Long) {
        val prefs = preferences(context)
        val now = System.currentTimeMillis()
        val zone = ZoneId.systemDefault()
        val today = LocalDate.now(zone)
        if (!mutateIfCurrent(prefs, generation) {
                prefs.edit().putLong(KEY_NEXT_AT, 0L).apply()
                val storedWindowEnd = prefs.getLong(KEY_WINDOW_END_AT, 0L)
                if (storedWindowEnd > 0L && now >= storedWindowEnd) {
                    cancelNotification(context)
                }
            }
        ) return
        val dataSource = SmartAlertDataSource(context)
        val capabilities = dataSource.capabilities()
        val setupReason = when {
            !notificationsAllowed(context) -> "notification_permission_required"
            !capabilities.stepsGranted -> "steps_permission_required"
            !capabilities.backgroundReadAvailable -> "background_read_unavailable"
            !capabilities.backgroundReadGranted -> "background_read_permission_required"
            else -> null
        }
        if (setupReason != null) {
            if (!mutateIfCurrent(prefs, generation) {
                    prefs.edit()
                        .putInt(KEY_BASELINE_STEPS, -1)
                        .putLong(KEY_INACTIVE_SINCE, 0L)
                        .putString(KEY_DEFER_REASON, setupReason)
                        .apply()
                }
            ) return
            enqueueSuccessor(context, generation, now + PERMISSION_RECHECK_MILLIS)
            return
        }

        val reading = try {
            dataSource.read(today, zone)
        } catch (_: SmartAlertDataSource.StepReadException) {
            if (!mutateIfCurrent(prefs, generation) {
                    prefs.edit()
                        .putInt(KEY_BASELINE_STEPS, -1)
                        .putLong(KEY_INACTIVE_SINCE, 0L)
                        .putString(KEY_DEFER_REASON, "unreliable_steps")
                        .apply()
                }
            ) return
            enqueueSuccessor(
                context,
                generation,
                now + SmartAlertPolicy.visibleNotificationRecheck.toMillis(),
            )
            return
        } catch (_: SmartAlertDataSource.TargetReadException) {
            if (!mutateIfCurrent(prefs, generation) {
                    prefs.edit()
                        .putInt(KEY_BASELINE_STEPS, -1)
                        .putLong(KEY_INACTIVE_SINCE, 0L)
                        .putString(KEY_DEFER_REASON, "unreliable_target")
                        .apply()
                }
            ) return
            enqueueSuccessor(
                context,
                generation,
                now + SmartAlertPolicy.visibleNotificationRecheck.toMillis(),
            )
            return
        }
        if (!synchronized(stateLock) { isCurrentGeneration(prefs, generation) }) return

        val nowZoned = Instant.ofEpochMilli(now).atZone(zone)
        val window = SmartAlertPolicy.activeWindowForMoment(
            now = nowZoned,
            wakeMinutes = reading.wakeMinutes,
            bedtimeMinutes = reading.bedtimeMinutes,
        )
        val windowStart = window.start.toInstant().toEpochMilli()
        val windowEnd = window.end.toInstant().toEpochMilli()
        val offsetSeconds = zone.rules.getOffset(Instant.ofEpochMilli(now)).totalSeconds
        val lastEvaluation = prefs.getLong(KEY_LAST_EVALUATION_AT, 0L)
        val resetNeeded = SmartAlertPolicy.requiresStateReset(
            storedDate = prefs.getString(KEY_STATE_DATE, null),
            currentDate = today,
            storedZone = prefs.getString(KEY_STATE_ZONE, null),
            currentZone = zone,
            storedOffsetSeconds = prefs.getInt(KEY_STATE_OFFSET, Int.MIN_VALUE)
                .takeUnless { it == Int.MIN_VALUE },
            currentOffsetSeconds = offsetSeconds,
            storedConfiguration = prefs.getString(KEY_CONFIGURATION, null),
            currentConfiguration = reading.configurationFingerprint,
            lastEvaluationAt = lastEvaluation,
            now = now,
        ) || prefs.getLong(KEY_TRACKING_START_AT, 0L) != windowStart ||
            prefs.getLong(KEY_WINDOW_END_AT, 0L) != windowEnd

        val previousStateDate = prefs.getString(KEY_STATE_DATE, null)
        if (resetNeeded) {
            val dateChanged = previousStateDate != today.toString()
            if (!mutateIfCurrent(prefs, generation) {
                    val resetEditor = prefs.edit()
                        .putString(KEY_STATE_DATE, today.toString())
                        .putString(KEY_STATE_ZONE, zone.id)
                        .putInt(KEY_STATE_OFFSET, offsetSeconds)
                        .putString(KEY_CONFIGURATION, reading.configurationFingerprint)
                        .putInt(KEY_BASELINE_STEPS, -1)
                        .putInt(KEY_LAST_OBSERVED_STEPS, reading.steps)
                        .putInt(KEY_OBSERVED_MOVEMENTS, reading.movements)
                        .putLong(KEY_INACTIVE_SINCE, 0L)
                        .putLong(KEY_LAST_MOVEMENT_EVENT_AT, 0L)
                        .putInt(KEY_ADAPTIVE_THRESHOLD, 0)
                    if (dateChanged) {
                        // The daily quota resets at midnight; the two-hour cooldown does not.
                        resetEditor.putInt(KEY_ALERTS_TODAY, 0)
                    }
                    resetEditor.apply()
                    cancelNotification(context)
                }
            ) return
        }

        if (!mutateIfCurrent(prefs, generation) {
                prefs.edit()
                    .putLong(KEY_TRACKING_START_AT, windowStart)
                    .putLong(KEY_WINDOW_END_AT, windowEnd)
                    .putLong(KEY_LAST_EVALUATION_AT, now)
                    .apply()
            }
        ) return

        if (!window.isAlertable) {
            if (!mutateIfCurrent(prefs, generation) {
                    prefs.edit()
                        .putInt(KEY_BASELINE_STEPS, -1)
                        .putLong(KEY_INACTIVE_SINCE, 0L)
                        .putString(KEY_DEFER_REASON, "outside_active_window")
                        .apply()
                }
            ) return
            enqueueSuccessor(
                context,
                generation,
                nextWindowStart(window.start.toLocalDate().plusDays(1), zone, reading),
            )
            return
        }

        if (now < windowStart || now >= windowEnd) {
            val nextDate = if (now < windowStart) {
                window.start.toLocalDate()
            } else {
                window.start.toLocalDate().plusDays(1)
            }
            val nextWindow = SmartAlertPolicy.activeWindow(
                date = nextDate,
                zone = zone,
                wakeMinutes = reading.wakeMinutes,
                bedtimeMinutes = reading.bedtimeMinutes,
            )
            if (!mutateIfCurrent(prefs, generation) {
                    cancelNotification(context)
                    prefs.edit()
                        .putInt(KEY_BASELINE_STEPS, -1)
                        .putLong(KEY_INACTIVE_SINCE, 0L)
                        .putString(KEY_DEFER_REASON, "outside_active_window")
                        .apply()
                }
            ) return
            enqueueSuccessor(context, generation, nextWindow.start.toInstant().toEpochMilli())
            return
        }

        val decision = synchronized(stateLock) {
            if (!isCurrentGeneration(prefs, generation)) return@synchronized null
            SmartAlertPolicy.evaluate(
                SmartAlertPolicy.Input(
                    now = now,
                    windowStart = windowStart,
                    windowEnd = windowEnd,
                    stepsReliable = true,
                    targetReliable = true,
                    currentSteps = reading.steps,
                    stepGoal = reading.stepGoal,
                    currentMovements = reading.movements,
                    movementGoal = reading.movementGoal,
                    baselineSteps = prefs.getInt(KEY_BASELINE_STEPS, -1)
                        .takeIf { it >= 0 },
                    inactiveSince = prefs.getLong(KEY_INACTIVE_SINCE, 0L)
                        .takeIf { it > 0L },
                    // Only the successful-insert channel is authoritative.
                    movementActivity = false,
                    lastAlertAt = prefs.getLong(KEY_LAST_ALERT_AT, 0L)
                        .takeIf { it > 0L },
                    alertsToday = prefs.getInt(KEY_ALERTS_TODAY, 0),
                    notificationVisible = notificationVisible(context),
                ),
            )
        } ?: return

        val finalized = synchronized(stateLock) {
            if (!isCurrentGeneration(prefs, generation)) {
                return@synchronized false to null
            }
            val editor = prefs.edit()
                .putInt(KEY_BASELINE_STEPS, decision.baselineSteps ?: -1)
                .putLong(KEY_INACTIVE_SINCE, decision.inactiveSince ?: 0L)
                .putInt(KEY_LAST_OBSERVED_STEPS, reading.steps)
                .putInt(KEY_OBSERVED_MOVEMENTS, reading.movements)
                .putString(KEY_DEFER_REASON, decision.deferReason)
                .putInt(KEY_ADAPTIVE_THRESHOLD, decision.adaptiveThreshold)

            var nextCheckAt = decision.nextCheckAt
            val nextLocalMidnight = today.plusDays(1).atStartOfDay(zone)
                .toInstant().toEpochMilli()
            when (decision.action) {
                SmartAlertPolicy.Action.ACTIVITY -> {
                    editor.putLong(KEY_LAST_ACTIVITY_AT, now)
                    cancelNotification(context)
                }
                SmartAlertPolicy.Action.GOALS_COMPLETE -> {
                    cancelNotification(context)
                    nextCheckAt = minOf(
                        now + PERMISSION_RECHECK_MILLIS,
                        windowEnd,
                        nextLocalMidnight,
                    )
                }
                SmartAlertPolicy.Action.ALERT -> {
                    if (showNotification(context, reading)) {
                        editor.putLong(KEY_LAST_ALERT_AT, now)
                            .putInt(
                                KEY_ALERTS_TODAY,
                                prefs.getInt(KEY_ALERTS_TODAY, 0) + 1,
                            )
                    } else {
                        editor.putString(KEY_DEFER_REASON, "notification_visible")
                        nextCheckAt = now +
                            SmartAlertPolicy.visibleNotificationRecheck.toMillis()
                    }
                }
                else -> Unit
            }
            if (decision.deferReason == "daily_limit") {
                nextCheckAt = nextLocalMidnight
            }
            if (
                decision.action != SmartAlertPolicy.Action.GOALS_COMPLETE &&
                nextCheckAt != null && nextCheckAt > windowEnd
            ) {
                nextCheckAt = windowEnd
            }
            editor.apply()
            true to nextCheckAt
        }
        if (!finalized.first) return
        enqueueSuccessor(context, generation, finalized.second)
    }

    internal fun markUnexpectedFailure(context: Context, generation: Long) {
        val prefs = preferences(context)
        mutateIfCurrent(prefs, generation) {
            prefs.edit()
                .putInt(KEY_BASELINE_STEPS, -1)
                .putLong(KEY_INACTIVE_SINCE, 0L)
                .putLong(KEY_NEXT_AT, System.currentTimeMillis() + 15L * 60L * 1000L)
                .putString(KEY_DEFER_REASON, "unreliable_steps")
                .apply()
        }
    }

    private fun nextWindowStart(
        date: LocalDate,
        zone: ZoneId,
        reading: SmartAlertDataSource.Reading,
    ): Long = SmartAlertPolicy.activeWindow(
        date = date,
        zone = zone,
        wakeMinutes = reading.wakeMinutes,
        bedtimeMinutes = reading.bedtimeMinutes,
    ).start.toInstant().toEpochMilli()
}

class SmartMovementAlertWorker(
    appContext: Context,
    workerParams: WorkerParameters,
) : CoroutineWorker(appContext, workerParams) {
    override suspend fun doWork(): Result {
        val generation = inputData.getLong("generation", -1L)
        if (generation < 0L) return Result.success()
        return try {
            ReminderScheduler.runCheck(applicationContext, generation)
            Result.success()
        } catch (_: Exception) {
            ReminderScheduler.markUnexpectedFailure(applicationContext, generation)
            Result.retry()
        }
    }
}

class MoveReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        // An old random alarm can race an upgrade. It must never notify.
        ReminderScheduler.initialize(context)
    }
}

class ReminderRestoreReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        ReminderScheduler.restore(context)
    }
}
