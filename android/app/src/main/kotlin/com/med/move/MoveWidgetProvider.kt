package com.med.move

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.icu.text.CompactDecimalFormat
import android.widget.RemoteViews
import java.util.Locale

class MoveWidgetProvider : AppWidgetProvider() {
    override fun onReceive(context: Context, intent: Intent?) {
        super.onReceive(context, intent)
        when (intent?.action) {
            Intent.ACTION_DATE_CHANGED,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED,
            -> updateAll(context)
        }
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        appWidgetIds.forEach { updateWidget(context, appWidgetManager, it) }
    }

    companion object {
        private const val OPEN_APP_REQUEST_CODE = 8201

        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val component = ComponentName(context, MoveWidgetProvider::class.java)
            manager.getAppWidgetIds(component).forEach {
                updateWidget(context, manager, it)
            }
        }

        private fun updateWidget(
            context: Context,
            manager: AppWidgetManager,
            widgetId: Int,
        ) {
            val snapshot = MoveStateStore.snapshot(context)
            val compactFormatter = CompactDecimalFormat.getInstance(
                Locale.US,
                CompactDecimalFormat.CompactStyle.SHORT,
            )
            val views = RemoteViews(context.packageName, R.layout.move_widget).apply {
                setTextViewText(
                    R.id.widget_streak,
                    if (snapshot.streak == 1) "1 day" else "${snapshot.streak} days",
                )
                setTextViewText(
                    R.id.widget_movements,
                    "${snapshot.movements} / ${snapshot.movementGoal}",
                )
                setTextViewText(
                    R.id.widget_steps,
                    "${compactFormatter.format(snapshot.steps)} / " +
                        compactFormatter.format(snapshot.stepGoal),
                )
                setProgressBar(
                    R.id.widget_movement_progress,
                    snapshot.movementGoal,
                    snapshot.movements.coerceAtMost(snapshot.movementGoal),
                    false,
                )
                setProgressBar(
                    R.id.widget_step_progress,
                    snapshot.stepGoal,
                    snapshot.steps.coerceAtMost(snapshot.stepGoal),
                    false,
                )
                setOnClickPendingIntent(R.id.widget_root, openAppIntent(context))
            }
            manager.updateAppWidget(widgetId, views)
        }

        private fun openAppIntent(context: Context): PendingIntent {
            val intent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            }
            return PendingIntent.getActivity(
                context,
                OPEN_APP_REQUEST_CODE,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
    }
}
