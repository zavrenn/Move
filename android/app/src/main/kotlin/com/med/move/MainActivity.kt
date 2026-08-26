package com.med.move

import android.Manifest
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.PermissionController
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.request.AggregateRequest
import androidx.health.connect.client.time.TimeRangeFilter
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.time.LocalDate
import java.time.ZoneId
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "com.med.move/device"
        private const val REQUEST_HEALTH_PERMISSIONS = 4101
        private const val REQUEST_NOTIFICATION_PERMISSION = 4102
    }

    private val activityScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val stepsPermission =
        HealthPermission.getReadPermission(StepsRecord::class)
    private val healthPermissions = setOf(stepsPermission)
    private val healthPermissionContract by lazy {
        PermissionController.createRequestPermissionResultContract()
    }

    private var pendingHealthPermissionResult: MethodChannel.Result? = null
    private var pendingNotificationPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ReminderScheduler.ensureNotificationChannel(this)
        ReminderScheduler.ensureScheduled(this)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler(::handleMethodCall)
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "healthStatus" -> healthStatus(result)
            "requestStepsPermission" -> requestStepsPermission(result)
            "readDailySteps" -> readDailySteps(call, result)
            "openHealthConnect" -> openHealthConnect(result)
            "reminderStatus" -> result.success(ReminderScheduler.status(this))
            "requestNotificationPermission" -> requestNotificationPermission(result)
            "setReminderEnabled" -> setReminderEnabled(call, result)
            "appPreferences" -> result.success(MoveStateStore.preferencesMap(this))
            "setDailyGoals" -> setDailyGoals(call, result)
            "setQuickMovementIds" -> setQuickMovementIds(call, result)
            "updateMoveSnapshot" -> updateMoveSnapshot(call, result)
            "homeWidgetStatus" -> homeWidgetStatus(result)
            "pinHomeWidget" -> pinHomeWidget(result)
            else -> result.notImplemented()
        }
    }

    private fun healthStatus(result: MethodChannel.Result) {
        when (HealthConnectClient.getSdkStatus(this)) {
            HealthConnectClient.SDK_AVAILABLE -> activityScope.launch {
                try {
                    val granted = healthClient()
                        .permissionController
                        .getGrantedPermissions()
                        .contains(stepsPermission)
                    result.success(if (granted) "connected" else "permissionRequired")
                } catch (error: Exception) {
                    result.error("health_status_failed", error.message, null)
                }
            }
            HealthConnectClient.SDK_UNAVAILABLE_PROVIDER_UPDATE_REQUIRED ->
                result.success("updateRequired")
            else -> result.success("unsupported")
        }
    }

    private fun requestStepsPermission(result: MethodChannel.Result) {
        if (HealthConnectClient.getSdkStatus(this) != HealthConnectClient.SDK_AVAILABLE) {
            result.error("health_unavailable", "Health Connect is unavailable.", null)
            return
        }
        if (pendingHealthPermissionResult != null) {
            result.error("request_in_progress", "A permission request is already open.", null)
            return
        }

        activityScope.launch {
            try {
                val granted = healthClient().permissionController.getGrantedPermissions()
                if (granted.containsAll(healthPermissions)) {
                    result.success(true)
                    return@launch
                }
                pendingHealthPermissionResult = result
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                    requestPermissions(
                        healthPermissions.toTypedArray(),
                        REQUEST_HEALTH_PERMISSIONS,
                    )
                } else {
                    val intent = healthPermissionContract.createIntent(
                        this@MainActivity,
                        healthPermissions,
                    )
                    startActivityForResult(intent, REQUEST_HEALTH_PERMISSIONS)
                }
            } catch (error: Exception) {
                pendingHealthPermissionResult = null
                result.error("health_permission_failed", error.message, null)
            }
        }
    }

    private fun readDailySteps(call: MethodCall, result: MethodChannel.Result) {
        val days = (call.argument<Int>("days") ?: 14).coerceIn(1, 30)
        if (HealthConnectClient.getSdkStatus(this) != HealthConnectClient.SDK_AVAILABLE) {
            result.error("health_unavailable", "Health Connect is unavailable.", null)
            return
        }

        activityScope.launch {
            try {
                val client = healthClient()
                val granted = client.permissionController.getGrantedPermissions()
                if (!granted.contains(stepsPermission)) {
                    result.error("health_permission_required", "Steps permission is required.", null)
                    return@launch
                }

                val zone = ZoneId.systemDefault()
                val today = LocalDate.now(zone)
                val values = mutableListOf<Map<String, Any>>()
                for (offset in (days - 1) downTo 0) {
                    val date = today.minusDays(offset.toLong())
                    val start = date.atStartOfDay(zone).toInstant()
                    val end = date.plusDays(1).atStartOfDay(zone).toInstant()
                    val aggregate = client.aggregate(
                        AggregateRequest(
                            metrics = setOf(StepsRecord.COUNT_TOTAL),
                            timeRangeFilter = TimeRangeFilter.between(start, end),
                        ),
                    )
                    values.add(
                        mapOf(
                            "date" to date.toString(),
                            "steps" to (aggregate[StepsRecord.COUNT_TOTAL] ?: 0L),
                        ),
                    )
                }
                result.success(values)
            } catch (error: SecurityException) {
                result.error("health_permission_required", error.message, null)
            } catch (error: Exception) {
                result.error("health_read_failed", error.message, null)
            }
        }
    }

    private fun openHealthConnect(result: MethodChannel.Result) {
        try {
            startActivity(HealthConnectClient.getHealthConnectManageDataIntent(this))
            result.success(null)
        } catch (error: Exception) {
            result.error("health_settings_failed", error.message, null)
        }
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (ReminderScheduler.notificationsAllowed(this)) {
            result.success(true)
            return
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success(true)
            return
        }
        if (pendingNotificationPermissionResult != null) {
            result.error("request_in_progress", "A permission request is already open.", null)
            return
        }
        pendingNotificationPermissionResult = result
        requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            REQUEST_NOTIFICATION_PERMISSION,
        )
    }

    private fun setReminderEnabled(call: MethodCall, result: MethodChannel.Result) {
        val enabled = call.argument<Boolean>("enabled") ?: false
        if (enabled && !ReminderScheduler.notificationsAllowed(this)) {
            result.error(
                "notification_permission_required",
                "Notification permission is required.",
                null,
            )
            return
        }
        ReminderScheduler.setEnabled(this, enabled)
        result.success(ReminderScheduler.status(this))
    }

    private fun setDailyGoals(call: MethodCall, result: MethodChannel.Result) {
        val stepGoal = call.argument<Int>("stepGoal") ?: MoveStateStore.DEFAULT_STEP_GOAL
        val movementGoal =
            call.argument<Int>("movementGoal") ?: MoveStateStore.DEFAULT_MOVEMENT_GOAL
        result.success(MoveStateStore.setGoals(this, stepGoal, movementGoal))
    }

    private fun setQuickMovementIds(call: MethodCall, result: MethodChannel.Result) {
        val ids = call.argument<List<*>>("ids")?.filterIsInstance<String>().orEmpty()
        if (ids.size !in 2..8) {
            result.error("invalid_quick_moves", "Choose between 2 and 8 Quick Moves.", null)
            return
        }
        MoveStateStore.setQuickMovementIds(this, ids)
        result.success(null)
    }

    private fun updateMoveSnapshot(call: MethodCall, result: MethodChannel.Result) {
        val date = call.argument<String>("date")
        if (date.isNullOrBlank()) {
            result.error("invalid_snapshot", "A snapshot date is required.", null)
            return
        }
        MoveStateStore.updateSnapshot(
            context = this,
            date = date,
            steps = call.argument<Int>("steps") ?: 0,
            movements = call.argument<Int>("movements") ?: 0,
            streak = call.argument<Int>("streak") ?: 0,
        )
        result.success(null)
    }

    private fun homeWidgetStatus(result: MethodChannel.Result) {
        val manager = AppWidgetManager.getInstance(this)
        val component = ComponentName(this, MoveWidgetProvider::class.java)
        result.success(
            mapOf(
                "supported" to manager.isRequestPinAppWidgetSupported,
                "active" to manager.getAppWidgetIds(component).isNotEmpty(),
            ),
        )
    }

    private fun pinHomeWidget(result: MethodChannel.Result) {
        val manager = AppWidgetManager.getInstance(this)
        if (!manager.isRequestPinAppWidgetSupported) {
            result.success(false)
            return
        }
        val provider = ComponentName(this, MoveWidgetProvider::class.java)
        result.success(manager.requestPinAppWidget(provider, null, null))
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == REQUEST_HEALTH_PERMISSIONS) {
            val granted = healthPermissionContract.parseResult(resultCode, data)
            pendingHealthPermissionResult?.success(granted.containsAll(healthPermissions))
            pendingHealthPermissionResult = null
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        if (requestCode == REQUEST_HEALTH_PERMISSIONS) {
            val granted = healthPermissions.all {
                checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED
            }
            pendingHealthPermissionResult?.success(granted)
            pendingHealthPermissionResult = null
            return
        }
        if (requestCode == REQUEST_NOTIFICATION_PERMISSION) {
            val granted = grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED
            pendingNotificationPermissionResult?.success(granted)
            pendingNotificationPermissionResult = null
            return
        }
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    private fun healthClient(): HealthConnectClient = HealthConnectClient.getOrCreate(this)

    override fun onDestroy() {
        pendingHealthPermissionResult?.error("activity_destroyed", "Permission request closed.", null)
        pendingNotificationPermissionResult?.error(
            "activity_destroyed",
            "Permission request closed.",
            null,
        )
        activityScope.cancel()
        super.onDestroy()
    }
}
