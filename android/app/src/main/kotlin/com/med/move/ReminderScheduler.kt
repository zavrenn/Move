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
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZonedDateTime
import java.util.concurrent.ThreadLocalRandom

object ReminderScheduler {
    private const val PREFS = "move_reminders"
    private const val KEY_ENABLED = "enabled"
    private const val KEY_NEXT_AT = "next_at"
    private const val KEY_LAST_REMINDER_DATE = "last_reminder_date"
    private const val CHANNEL_ID = "move_daily_reminder"
    private const val ALARM_REQUEST_CODE = 7021
    private const val NOTIFICATION_ID = 7022
    private const val START_HOUR = 5
    private const val END_HOUR = 23
    private const val ALARM_WINDOW_MILLIS = 10L * 60L * 1000L

    fun setEnabled(context: Context, enabled: Boolean) {
        preferences(context).edit().putBoolean(KEY_ENABLED, enabled).apply()
        if (enabled) {
            ensureNotificationChannel(context)
            scheduleFromNow(context, force = true)
        } else {
            cancel(context)
        }
    }

    fun status(context: Context): Map<String, Any> {
        val prefs = preferences(context)
        return mapOf(
            "enabled" to prefs.getBoolean(KEY_ENABLED, false),
            "notificationGranted" to notificationsAllowed(context),
            "nextAt" to prefs.getLong(KEY_NEXT_AT, 0L),
            "startHour" to START_HOUR,
            "endHour" to END_HOUR,
        )
    }

    fun notificationsAllowed(context: Context): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
    }

    fun ensureNotificationChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java)
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Daily movement reminder",
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            description = "One friendly reminder to move during the day"
            enableVibration(true)
        }
        manager.createNotificationChannel(channel)
    }

    fun ensureScheduled(context: Context) {
        scheduleFromNow(context, force = false)
    }

    fun restore(context: Context) {
        scheduleFromNow(context, force = true)
    }

    fun scheduleTomorrow(context: Context) {
        if (!preferences(context).getBoolean(KEY_ENABLED, false)) return
        val tomorrow = LocalDate.now(ZoneId.systemDefault()).plusDays(1)
        scheduleForDate(context, tomorrow)
    }

    private fun scheduleFromNow(context: Context, force: Boolean) {
        val prefs = preferences(context)
        if (!prefs.getBoolean(KEY_ENABLED, false)) return
        val currentNext = prefs.getLong(KEY_NEXT_AT, 0L)
        if (!force && currentNext > System.currentTimeMillis()) return

        val zone = ZoneId.systemDefault()
        val now = ZonedDateTime.now(zone)
        val date = nextScheduleDate(now, lastReminderDate(prefs))
        scheduleForDate(context, date)
    }

    internal fun nextScheduleDate(
        now: ZonedDateTime,
        lastReminderDate: LocalDate?,
    ): LocalDate {
        val today = now.toLocalDate()
        if (lastReminderDate == today) return today.plusDays(1)

        val todayEnd = today.atTime(END_HOUR, 0).atZone(now.zone)
        return if (now.plusMinutes(10).isBefore(todayEnd)) today else today.plusDays(1)
    }

    private fun scheduleForDate(context: Context, date: LocalDate) {
        val zone = ZoneId.systemDefault()
        val now = ZonedDateTime.now(zone)
        val dayStart = date.atTime(START_HOUR, 0).atZone(zone)
        val dayEnd = date.atTime(END_HOUR, 0).atZone(zone)
        val latestStart = dayEnd.minusMinutes(10)
        val earliest = if (date == now.toLocalDate() && now.plusMinutes(10).isAfter(dayStart)) {
            now.plusMinutes(10)
        } else {
            dayStart
        }
        if (!earliest.isBefore(latestStart)) {
            scheduleForDate(context, date.plusDays(1))
            return
        }

        val triggerAt = ThreadLocalRandom.current().nextLong(
            earliest.toInstant().toEpochMilli(),
            latestStart.toInstant().toEpochMilli(),
        )
        val alarmManager = context.getSystemService(AlarmManager::class.java)
        alarmManager.setWindow(
            AlarmManager.RTC_WAKEUP,
            triggerAt,
            ALARM_WINDOW_MILLIS,
            alarmPendingIntent(context),
        )
        preferences(context).edit().putLong(KEY_NEXT_AT, triggerAt).apply()
    }

    private fun cancel(context: Context) {
        val alarmManager = context.getSystemService(AlarmManager::class.java)
        alarmManager.cancel(alarmPendingIntent(context))
        preferences(context).edit().putLong(KEY_NEXT_AT, 0L).apply()
    }

    private fun alarmPendingIntent(context: Context): PendingIntent {
        val intent = Intent(context, MoveReminderReceiver::class.java)
        return PendingIntent.getBroadcast(
            context,
            ALARM_REQUEST_CODE,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun preferences(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun lastReminderDate(preferences: android.content.SharedPreferences): LocalDate? {
        val stored = preferences.getString(KEY_LAST_REMINDER_DATE, null) ?: return null
        return runCatching { LocalDate.parse(stored) }.getOrNull()
    }

    internal fun handleReminder(context: Context): Boolean {
        val prefs = preferences(context)
        if (!prefs.getBoolean(KEY_ENABLED, false)) return false

        val today = LocalDate.now(ZoneId.systemDefault())
        if (lastReminderDate(prefs) == today) return false

        prefs.edit()
            .putString(KEY_LAST_REMINDER_DATE, today.toString())
            .putLong(KEY_NEXT_AT, 0L)
            .apply()
        showNotification(context)
        return true
    }

    internal fun showNotification(context: Context) {
        if (!notificationsAllowed(context)) return
        val snapshot = MoveStateStore.snapshot(context)
        if (snapshot.isCurrentDay && snapshot.goalsComplete) return
        ensureNotificationChannel(context)
        val copy = reminderCopy(snapshot)
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
            .setContentIntent(openApp)
            .setAutoCancel(true)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .build()
        context.getSystemService(NotificationManager::class.java)
            .notify(NOTIFICATION_ID, notification)
    }

    private fun reminderCopy(snapshot: MoveStateStore.Snapshot): Pair<String, String> {
        if (!snapshot.isCurrentDay) {
            return "Time to move" to genericMessages().random()
        }

        val movementComplete = snapshot.movements >= snapshot.movementGoal
        val stepsComplete = snapshot.steps >= snapshot.stepGoal
        return when {
            movementComplete && !stepsComplete ->
                "Movement goal complete" to
                    "A short walk can keep today’s rhythm going."
            stepsComplete && !movementComplete ->
                "Step goal complete" to
                    "Your steps are in—one quick movement set can round out the day."
            snapshot.movements > 0 || snapshot.steps > 0 ->
                "Keep the momentum" to
                    "You’re already moving. A small reset can bring both goals closer."
            else -> "Time to move" to genericMessages().random()
        }
    }

    private fun genericMessages() = listOf(
        "A small move is still a move.",
        "Stand up, stretch, and reset for a minute.",
        "Give your body a quick movement break.",
        "A few steps or a short stretch can reset your day.",
        "Keep the rhythm going—move a little.",
    )
}

class MoveReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (ReminderScheduler.handleReminder(context)) {
            ReminderScheduler.scheduleTomorrow(context)
        }
    }
}

class ReminderRestoreReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        ReminderScheduler.restore(context)
    }
}
