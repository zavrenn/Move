package com.med.move

import android.Manifest
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.PermissionController
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.SleepSessionRecord
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.records.metadata.DataOrigin
import androidx.health.connect.client.request.AggregateRequest
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import com.samsung.android.sdk.health.data.HealthDataService
import com.samsung.android.sdk.health.data.HealthDataStore
import com.samsung.android.sdk.health.data.error.AuthorizationException
import com.samsung.android.sdk.health.data.error.ErrorCode
import com.samsung.android.sdk.health.data.error.HealthDataException
import com.samsung.android.sdk.health.data.error.ResolvablePlatformException
import com.samsung.android.sdk.health.data.permission.AccessType
import com.samsung.android.sdk.health.data.permission.Permission
import com.samsung.android.sdk.health.data.request.DataType
import com.samsung.android.sdk.health.data.request.DataTypes
import com.samsung.android.sdk.health.data.request.LocalDateFilter
import com.samsung.android.sdk.health.data.request.Ordering
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.time.Duration
import java.time.LocalDate
import java.time.LocalTime
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
        private const val REQUEST_NOTIFICATION_SETTINGS = 4103
        private const val SAMSUNG_HEALTH_PACKAGE = "com.sec.android.app.shealth"
    }

    private val activityScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val stepsPermission =
        HealthPermission.getReadPermission(StepsRecord::class)
    private val sleepPermission =
        HealthPermission.getReadPermission(SleepSessionRecord::class)
    private val backgroundReadPermission = SmartAlertDataSource.backgroundPermission
    private val samsungSleepGoalPermission =
        Permission.of(DataTypes.SLEEP_GOAL, AccessType.READ)
    private val samsungSleepGoalPermissions = setOf(samsungSleepGoalPermission)
    private val samsungStepGoalPermission =
        Permission.of(DataTypes.STEPS_GOAL, AccessType.READ)
    private val samsungStepGoalPermissions = setOf(samsungStepGoalPermission)
    private val healthPermissionContract by lazy {
        PermissionController.createRequestPermissionResultContract()
    }

    private var pendingHealthPermissionResult: MethodChannel.Result? = null
    private var pendingHealthPermissions: Set<String>? = null
    private var pendingHealthPermissionReturnsSmartStatus = false
    private var pendingNotificationPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ReminderScheduler.initialize(this)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler(::handleMethodCall)
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "healthStatus" -> healthStatus(result)
            "requestStepsPermission" -> requestStepsPermission(result)
            "readDailySteps" -> readDailySteps(call, result)
            "sleepStatus" -> sleepStatus(result)
            "requestSleepPermission" -> requestSleepPermission(result)
            "readDailySleep" -> readDailySleep(call, result)
            "samsungSleepTargetStatus" -> samsungSleepTargetStatus(result)
            "requestSamsungSleepTargetPermission" ->
                requestSamsungSleepTargetPermission(result)
            "readSamsungSleepTarget" -> readSamsungSleepTarget(result)
            "samsungStepTargetStatus" -> samsungStepTargetStatus(result)
            "requestSamsungStepTargetPermission" ->
                requestSamsungStepTargetPermission(result)
            "readSamsungStepTarget" -> readSamsungStepTarget(result)
            "openHealthConnect" -> openHealthConnect(result)
            "reminderStatus", "smartAlertStatus" -> smartAlertStatus(result)
            "requestSmartAlertPermissions" -> requestSmartAlertPermissions(result)
            "requestNotificationPermission" -> requestNotificationPermission(result)
            "setReminderEnabled", "setSmartAlertsEnabled" ->
                setReminderEnabled(call, result)
            "recordMovementActivity" -> recordMovementActivity(call, result)
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
        permissionStatus(stepsPermission, result)
    }

    private fun sleepStatus(result: MethodChannel.Result) {
        permissionStatus(sleepPermission, result)
    }

    private fun permissionStatus(permission: String, result: MethodChannel.Result) {
        when (HealthConnectClient.getSdkStatus(this)) {
            HealthConnectClient.SDK_AVAILABLE -> activityScope.launch {
                try {
                    val granted = healthClient()
                        .permissionController
                        .getGrantedPermissions()
                        .contains(permission)
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
        requestHealthPermissions(setOf(stepsPermission), result)
    }

    private fun requestSleepPermission(result: MethodChannel.Result) {
        requestHealthPermissions(setOf(sleepPermission), result)
    }

    private fun requestHealthPermissions(
        permissions: Set<String>,
        result: MethodChannel.Result,
        returnSmartStatus: Boolean = false,
    ) {
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
                if (granted.containsAll(permissions)) {
                    if (returnSmartStatus) {
                        result.success(ReminderScheduler.status(this@MainActivity))
                    } else {
                        result.success(true)
                    }
                    return@launch
                }
                pendingHealthPermissionResult = result
                pendingHealthPermissions = permissions
                pendingHealthPermissionReturnsSmartStatus = returnSmartStatus
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                    requestPermissions(
                        permissions.toTypedArray(),
                        REQUEST_HEALTH_PERMISSIONS,
                    )
                } else {
                    val intent = healthPermissionContract.createIntent(
                        this@MainActivity,
                        permissions,
                    )
                    startActivityForResult(intent, REQUEST_HEALTH_PERMISSIONS)
                }
            } catch (error: Exception) {
                pendingHealthPermissionResult = null
                pendingHealthPermissions = null
                pendingHealthPermissionReturnsSmartStatus = false
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
                            dataOriginFilter = setOf(DataOrigin(SAMSUNG_HEALTH_PACKAGE)),
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

    private data class SleepCandidate(
        val date: LocalDate,
        val sleepStart: Long,
        val sleepEnd: Long,
        val asleepMinutes: Int,
        val sourcePackage: String,
    )

    private fun readDailySleep(call: MethodCall, result: MethodChannel.Result) {
        val days = (call.argument<Int>("days") ?: 14).coerceIn(1, 30)
        if (HealthConnectClient.getSdkStatus(this) != HealthConnectClient.SDK_AVAILABLE) {
            result.error("health_unavailable", "Health Connect is unavailable.", null)
            return
        }

        activityScope.launch {
            try {
                val client = healthClient()
                val granted = client.permissionController.getGrantedPermissions()
                if (!granted.contains(sleepPermission)) {
                    result.error("health_permission_required", "Sleep permission is required.", null)
                    return@launch
                }

                val zone = ZoneId.systemDefault()
                val today = LocalDate.now(zone)
                val firstDate = today.minusDays((days - 1).toLong())
                val records = mutableListOf<SleepSessionRecord>()
                var pageToken: String? = null
                do {
                    val response = client.readRecords(
                        ReadRecordsRequest(
                            recordType = SleepSessionRecord::class,
                            timeRangeFilter = TimeRangeFilter.between(
                                firstDate.minusDays(1).atStartOfDay(zone).toInstant(),
                                today.plusDays(1).atStartOfDay(zone).toInstant(),
                            ),
                            pageToken = pageToken,
                        ),
                    )
                    records.addAll(response.records)
                    pageToken = response.pageToken
                } while (pageToken != null)

                val candidates = records.mapNotNull { record ->
                    val sleepingStages = record.stages.filter { stage ->
                        stage.stage == SleepSessionRecord.STAGE_TYPE_SLEEPING ||
                            stage.stage == SleepSessionRecord.STAGE_TYPE_LIGHT ||
                            stage.stage == SleepSessionRecord.STAGE_TYPE_DEEP ||
                            stage.stage == SleepSessionRecord.STAGE_TYPE_REM
                    }
                    val sleepStart = sleepingStages.minOfOrNull { it.startTime }
                        ?: record.startTime
                    val sleepEnd = sleepingStages.maxOfOrNull { it.endTime }
                        ?: record.endTime
                    val wakeDate = sleepEnd.atZone(zone).toLocalDate()
                    if (wakeDate.isBefore(firstDate) || wakeDate.isAfter(today)) {
                        return@mapNotNull null
                    }
                    val asleepMinutes = if (sleepingStages.isEmpty()) {
                        Duration.between(sleepStart, sleepEnd).toMinutes()
                    } else {
                        sleepingStages.sumOf {
                            Duration.between(it.startTime, it.endTime).toMinutes()
                        }
                    }.coerceIn(0L, 1440L).toInt()
                    SleepCandidate(
                        date = wakeDate,
                        sleepStart = sleepStart.toEpochMilli(),
                        sleepEnd = sleepEnd.toEpochMilli(),
                        asleepMinutes = asleepMinutes,
                        sourcePackage = record.metadata.dataOrigin.packageName,
                    )
                }

                val values = candidates.groupBy { it.date }.mapNotNull { (date, records) ->
                    val samsungRecords = records.filter {
                        it.sourcePackage == SAMSUNG_HEALTH_PACKAGE
                    }
                    val selected = (samsungRecords.ifEmpty { records })
                        .maxByOrNull { it.asleepMinutes }
                        ?: return@mapNotNull null
                    mapOf(
                        "date" to date.toString(),
                        "sleepStart" to selected.sleepStart,
                        "sleepEnd" to selected.sleepEnd,
                    )
                }.sortedBy { it["date"] as String }
                result.success(
                    mapOf(
                        "startDate" to firstDate.toString(),
                        "endDate" to today.toString(),
                        "records" to values,
                    ),
                )
            } catch (error: SecurityException) {
                result.error("health_permission_required", error.message, null)
            } catch (error: Exception) {
                result.error("health_sleep_read_failed", error.message, null)
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

    private data class SamsungSleepGoal(
        val bedtime: LocalTime,
        val wakeTime: LocalTime,
    )

    private data class SamsungStepGoal(
        val steps: Int,
        val localDate: LocalDate,
    )

    private fun samsungSleepTargetStatus(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            result.success("unsupported")
            return
        }
        activityScope.launch {
            try {
                val granted = samsungStore()
                    .getGrantedPermissions(samsungSleepGoalPermissions)
                    .contains(samsungSleepGoalPermission)
                result.success(if (granted) "connected" else "permissionRequired")
            } catch (error: HealthDataException) {
                result.success(samsungStatus(error))
            } catch (_: Exception) {
                result.success("error")
            }
        }
    }

    private fun requestSamsungSleepTargetPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            result.error("samsung_health_unsupported", "Android 10 or newer is required.", null)
            return
        }
        activityScope.launch {
            try {
                val granted = samsungStore().requestPermissions(
                    samsungSleepGoalPermissions,
                    this@MainActivity,
                )
                result.success(granted.contains(samsungSleepGoalPermission))
            } catch (error: ResolvablePlatformException) {
                if (error.hasResolution) {
                    error.resolve(this@MainActivity)
                    result.success(false)
                } else {
                    result.error(samsungErrorKey(error), error.errorMessage, error.errorCode)
                }
            } catch (error: HealthDataException) {
                result.error(samsungErrorKey(error), error.errorMessage, error.errorCode)
            } catch (error: Exception) {
                result.error("samsung_health_error", error.message, null)
            }
        }
    }

    private fun readSamsungSleepTarget(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            result.error("samsung_health_unsupported", "Android 10 or newer is required.", null)
            return
        }
        activityScope.launch {
            try {
                val store = samsungStore()
                val granted = store.getGrantedPermissions(samsungSleepGoalPermissions)
                if (!granted.contains(samsungSleepGoalPermission)) {
                    result.error(
                        "samsung_sleep_goal_permission_required",
                        "Samsung Health sleep goal permission is required.",
                        null,
                    )
                    return@launch
                }
                val goal = readSamsungSleepGoal(store)
                result.success(
                    goal?.let {
                        mapOf(
                            "bedtimeMinutes" to it.bedtime.hour * 60 + it.bedtime.minute,
                            "wakeMinutes" to it.wakeTime.hour * 60 + it.wakeTime.minute,
                        )
                    },
                )
            } catch (error: HealthDataException) {
                result.error(samsungErrorKey(error), error.errorMessage, error.errorCode)
            } catch (error: Exception) {
                result.error("samsung_health_error", error.message, null)
            }
        }
    }

    private suspend fun readSamsungSleepGoal(store: HealthDataStore): SamsungSleepGoal? {
        val today = LocalDate.now()
        val dateFilter = LocalDateFilter.of(today, today, true, true)
        val bedtimeRequest = DataType.SleepGoalType.LAST_BED_TIME.requestBuilder
            .setLocalDateFilter(dateFilter)
            .setOrdering(Ordering.DESC)
            .build()
        val wakeRequest = DataType.SleepGoalType.LAST_WAKE_UP_TIME.requestBuilder
            .setLocalDateFilter(dateFilter)
            .setOrdering(Ordering.DESC)
            .build()
        val bedtime = store.aggregateData(bedtimeRequest).dataList
            .firstOrNull()?.value ?: return null
        val wakeTime = store.aggregateData(wakeRequest).dataList
            .firstOrNull()?.value ?: return null
        return SamsungSleepGoal(bedtime = bedtime, wakeTime = wakeTime)
    }

    private fun samsungStepTargetStatus(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            result.success("unsupported")
            return
        }
        activityScope.launch {
            try {
                val granted = samsungStore()
                    .getGrantedPermissions(samsungStepGoalPermissions)
                    .contains(samsungStepGoalPermission)
                result.success(if (granted) "connected" else "permissionRequired")
            } catch (error: HealthDataException) {
                result.success(samsungStatus(error))
            } catch (_: Exception) {
                result.success("error")
            }
        }
    }

    private fun requestSamsungStepTargetPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            result.error("samsung_health_unsupported", "Android 10 or newer is required.", null)
            return
        }
        activityScope.launch {
            try {
                val granted = samsungStore().requestPermissions(
                    samsungStepGoalPermissions,
                    this@MainActivity,
                )
                result.success(granted.contains(samsungStepGoalPermission))
            } catch (error: ResolvablePlatformException) {
                if (error.hasResolution) {
                    error.resolve(this@MainActivity)
                    result.success(false)
                } else {
                    result.error(
                        samsungErrorKey(error, "samsung_step_goal_permission_required"),
                        error.errorMessage,
                        error.errorCode,
                    )
                }
            } catch (error: HealthDataException) {
                result.error(
                    samsungErrorKey(error, "samsung_step_goal_permission_required"),
                    error.errorMessage,
                    error.errorCode,
                )
            } catch (error: Exception) {
                result.error("samsung_health_error", error.message, null)
            }
        }
    }

    private fun readSamsungStepTarget(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            result.error("samsung_health_unsupported", "Android 10 or newer is required.", null)
            return
        }
        activityScope.launch {
            try {
                val store = samsungStore()
                val granted = store.getGrantedPermissions(samsungStepGoalPermissions)
                if (!granted.contains(samsungStepGoalPermission)) {
                    result.error(
                        "samsung_step_goal_permission_required",
                        "Samsung Health step goal permission is required.",
                        null,
                    )
                    return@launch
                }
                val goal = readSamsungStepGoal(store)
                result.success(
                    goal?.let {
                        mapOf(
                            "steps" to it.steps,
                            "date" to it.localDate.toString(),
                        )
                    },
                )
            } catch (error: HealthDataException) {
                result.error(
                    samsungErrorKey(error, "samsung_step_goal_permission_required"),
                    error.errorMessage,
                    error.errorCode,
                )
            } catch (error: Exception) {
                result.error("samsung_health_error", error.message, null)
            }
        }
    }

    private suspend fun readSamsungStepGoal(store: HealthDataStore): SamsungStepGoal? {
        val today = LocalDate.now()
        val request = DataType.StepsGoalType.LAST.requestBuilder
            .setLocalDateFilter(LocalDateFilter.of(today, today.plusDays(1)))
            .build()
        val steps = store.aggregateData(request).dataList
            .lastOrNull()?.value?.takeIf { it > 0 } ?: return null
        return SamsungStepGoal(steps = steps, localDate = today)
    }

    private fun samsungStore(): HealthDataStore =
        HealthDataService.getStore(applicationContext)

    private fun samsungStatus(error: HealthDataException): String = when (error) {
        is ResolvablePlatformException -> when (error.errorCode) {
            ErrorCode.ERR_PLATFORM_NOT_INSTALLED -> "notInstalled"
            ErrorCode.ERR_OLD_VERSION_PLATFORM -> "updateRequired"
            ErrorCode.ERR_PLATFORM_DISABLED -> "disabled"
            ErrorCode.ERR_PLATFORM_NOT_INITIALIZED -> "notInitialized"
            else -> "unavailable"
        }
        is AuthorizationException -> when (error.errorCode) {
            ErrorCode.ERR_NO_USER_PERMISSION -> "permissionRequired"
            ErrorCode.ERR_UNSUPPORTED_OPERATION -> "unsupported"
            else -> "authorizationRequired"
        }
        else -> "error"
    }

    private fun samsungErrorKey(
        error: HealthDataException,
        permissionRequiredKey: String = "samsung_sleep_goal_permission_required",
    ): String = when (error) {
        is ResolvablePlatformException -> when (error.errorCode) {
            ErrorCode.ERR_PLATFORM_NOT_INSTALLED -> "samsung_health_not_installed"
            ErrorCode.ERR_OLD_VERSION_PLATFORM -> "samsung_health_update_required"
            ErrorCode.ERR_PLATFORM_DISABLED -> "samsung_health_disabled"
            ErrorCode.ERR_PLATFORM_NOT_INITIALIZED -> "samsung_health_not_initialized"
            else -> "samsung_health_unavailable"
        }
        is AuthorizationException -> when (error.errorCode) {
            ErrorCode.ERR_NO_USER_PERMISSION -> permissionRequiredKey
            ErrorCode.ERR_ACCESS_CONTROL -> "samsung_health_sdk_policy_denied"
            ErrorCode.ERR_UNSUPPORTED_OPERATION -> "samsung_health_unsupported"
            ErrorCode.ERR_INVALID_PLATFORM_SIGNATURE -> "samsung_health_invalid_platform"
            ErrorCode.ERR_CHILD_ACCOUNT_ACCESS -> "samsung_health_child_account"
            else -> "samsung_health_not_authorized"
        }
        else -> "samsung_health_error"
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (ReminderScheduler.notificationsAllowed(this)) {
            result.success(true)
            return
        }
        if (pendingNotificationPermissionResult != null) {
            result.error("request_in_progress", "A permission request is already open.", null)
            return
        }
        pendingNotificationPermissionResult = result
        if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                REQUEST_NOTIFICATION_PERMISSION,
            )
            return
        }
        try {
            startActivityForResult(
                Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                    putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                },
                REQUEST_NOTIFICATION_SETTINGS,
            )
        } catch (error: Exception) {
            pendingNotificationPermissionResult = null
            result.error("notification_settings_failed", error.message, null)
        }
    }

    private fun smartAlertStatus(result: MethodChannel.Result) {
        activityScope.launch {
            result.success(ReminderScheduler.status(this@MainActivity))
        }
    }

    private fun requestSmartAlertPermissions(result: MethodChannel.Result) {
        if (HealthConnectClient.getSdkStatus(this) != HealthConnectClient.SDK_AVAILABLE) {
            smartAlertStatus(result)
            return
        }
        activityScope.launch {
            val capabilities = SmartAlertDataSource(this@MainActivity).capabilities()
            val requested = buildSet {
                add(stepsPermission)
                if (capabilities.backgroundReadAvailable) add(backgroundReadPermission)
            }
            requestHealthPermissions(
                permissions = requested,
                result = result,
                returnSmartStatus = true,
            )
        }
    }

    private fun setReminderEnabled(call: MethodCall, result: MethodChannel.Result) {
        val enabled = call.argument<Boolean>("enabled") ?: false
        if (!enabled) {
            ReminderScheduler.setEnabled(this, false)
            smartAlertStatus(result)
            return
        }
        if (!ReminderScheduler.notificationsAllowed(this)) {
            result.error(
                "notification_permission_required",
                "Notification permission is required.",
                null,
            )
            return
        }
        activityScope.launch {
            val capabilities = SmartAlertDataSource(this@MainActivity).capabilities()
            val error = when {
                !capabilities.stepsGranted ->
                    "steps_permission_required" to "Health Connect steps access is required."
                !capabilities.backgroundReadAvailable ->
                    "background_read_unavailable" to
                        "Background Health Connect access requires Android 14+ and a current provider."
                !capabilities.backgroundReadGranted ->
                    "background_read_permission_required" to
                        "Health Connect background access is required."
                else -> null
            }
            if (error != null) {
                result.error(error.first, error.second, null)
                return@launch
            }
            ReminderScheduler.setEnabled(this@MainActivity, true)
            result.success(ReminderScheduler.status(this@MainActivity))
        }
    }

    private fun recordMovementActivity(call: MethodCall, result: MethodChannel.Result) {
        val createdAt = call.argument<Number>("createdAt")?.toLong()
            ?: System.currentTimeMillis()
        ReminderScheduler.recordMovementActivity(this, createdAt)
        result.success(null)
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
            stepGoal = call.argument<Int>("stepGoal") ?: MoveStateStore.DEFAULT_STEP_GOAL,
            usesSamsungStepGoal = call.argument<Boolean>("usesSamsungStepGoal") ?: false,
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
        if (requestCode == REQUEST_NOTIFICATION_SETTINGS) {
            pendingNotificationPermissionResult?.success(
                ReminderScheduler.notificationsAllowed(this),
            )
            pendingNotificationPermissionResult = null
            return
        }
        if (requestCode == REQUEST_HEALTH_PERMISSIONS) {
            val granted = healthPermissionContract.parseResult(resultCode, data)
            val pendingResult = pendingHealthPermissionResult
            val requestedPermissions = pendingHealthPermissions.orEmpty()
            val returnStatus = pendingHealthPermissionReturnsSmartStatus
            pendingHealthPermissionResult = null
            pendingHealthPermissions = null
            pendingHealthPermissionReturnsSmartStatus = false
            if (returnStatus) {
                activityScope.launch {
                    if (ReminderScheduler.isEnabled(this@MainActivity)) {
                        ReminderScheduler.onConfigurationChanged(this@MainActivity)
                    }
                    pendingResult?.success(ReminderScheduler.status(this@MainActivity))
                }
            } else {
                pendingResult?.success(granted.containsAll(requestedPermissions))
            }
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
            val granted = pendingHealthPermissions.orEmpty().all {
                checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED
            }
            val pendingResult = pendingHealthPermissionResult
            val returnStatus = pendingHealthPermissionReturnsSmartStatus
            pendingHealthPermissionResult = null
            pendingHealthPermissions = null
            pendingHealthPermissionReturnsSmartStatus = false
            if (returnStatus) {
                activityScope.launch {
                    if (ReminderScheduler.isEnabled(this@MainActivity)) {
                        ReminderScheduler.onConfigurationChanged(this@MainActivity)
                    }
                    pendingResult?.success(ReminderScheduler.status(this@MainActivity))
                }
            } else {
                pendingResult?.success(granted)
            }
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
        pendingHealthPermissions = null
        pendingHealthPermissionReturnsSmartStatus = false
        pendingNotificationPermissionResult?.error(
            "activity_destroyed",
            "Permission request closed.",
            null,
        )
        activityScope.cancel()
        super.onDestroy()
    }
}
