package com.med.move

import android.content.Context
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.HealthConnectFeatures
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.records.metadata.DataOrigin
import androidx.health.connect.client.request.AggregateRequest
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
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId

internal class SmartAlertDataSource(context: Context) {
    companion object {
        const val SAMSUNG_HEALTH_PACKAGE = "com.sec.android.app.shealth"
        val stepsPermission: String = HealthPermission.getReadPermission(StepsRecord::class)
        val backgroundPermission: String =
            HealthPermission.PERMISSION_READ_HEALTH_DATA_IN_BACKGROUND

        private val samsungSleepGoalPermission =
            Permission.of(DataTypes.SLEEP_GOAL, AccessType.READ)
        private val samsungStepGoalPermission =
            Permission.of(DataTypes.STEPS_GOAL, AccessType.READ)
        private val samsungGoalPermissions = setOf(
            samsungSleepGoalPermission,
            samsungStepGoalPermission,
        )
    }

    data class Capabilities(
        val healthConnectAvailable: Boolean,
        val stepsGranted: Boolean,
        val backgroundReadAvailable: Boolean,
        val backgroundReadGranted: Boolean,
    )

    data class Reading(
        val steps: Int,
        val stepGoal: Int,
        val movementGoal: Int,
        val movements: Int,
        val wakeMinutes: Int?,
        val bedtimeMinutes: Int?,
        val usesSamsungStepGoal: Boolean,
        val usesSamsungSleepGoal: Boolean,
    ) {
        val configurationFingerprint: String
            get() = listOf(
                stepGoal,
                movementGoal,
                wakeMinutes ?: -1,
                bedtimeMinutes ?: -1,
                usesSamsungStepGoal,
                usesSamsungSleepGoal,
            ).joinToString(":")
    }

    class StepReadException(message: String?, cause: Throwable? = null) :
        Exception(message, cause)

    class TargetReadException(message: String?, cause: Throwable? = null) :
        Exception(message, cause)

    private val appContext = context.applicationContext

    suspend fun capabilities(): Capabilities {
        if (HealthConnectClient.getSdkStatus(appContext) != HealthConnectClient.SDK_AVAILABLE) {
            return Capabilities(
                healthConnectAvailable = false,
                stepsGranted = false,
                backgroundReadAvailable = false,
                backgroundReadGranted = false,
            )
        }
        val client = HealthConnectClient.getOrCreate(appContext)
        val backgroundAvailable = runCatching {
            client.features.getFeatureStatus(
                HealthConnectFeatures.FEATURE_READ_HEALTH_DATA_IN_BACKGROUND,
            ) == HealthConnectFeatures.FEATURE_STATUS_AVAILABLE
        }.getOrDefault(false)
        val granted = runCatching {
            client.permissionController.getGrantedPermissions()
        }.getOrDefault(emptySet())
        return Capabilities(
            healthConnectAvailable = true,
            stepsGranted = granted.contains(stepsPermission),
            backgroundReadAvailable = backgroundAvailable,
            backgroundReadGranted = backgroundAvailable && granted.contains(backgroundPermission),
        )
    }

    suspend fun read(nowDate: LocalDate, zone: ZoneId): Reading {
        val capabilities = capabilities()
        if (!capabilities.stepsGranted || !capabilities.backgroundReadGranted) {
            throw StepReadException("Health Connect background step access is unavailable.")
        }

        val steps = try {
            val start = nowDate.atStartOfDay(zone).toInstant()
            val end = nowDate.plusDays(1).atStartOfDay(zone).toInstant()
            val aggregate = HealthConnectClient.getOrCreate(appContext).aggregate(
                AggregateRequest(
                    metrics = setOf(StepsRecord.COUNT_TOTAL),
                    timeRangeFilter = TimeRangeFilter.between(start, end),
                    dataOriginFilter = setOf(DataOrigin(SAMSUNG_HEALTH_PACKAGE)),
                ),
            )
            (aggregate[StepsRecord.COUNT_TOTAL] ?: 0L)
                .coerceIn(0L, Int.MAX_VALUE.toLong())
                .toInt()
        } catch (error: Exception) {
            throw StepReadException(error.message, error)
        }

        val snapshot = MoveStateStore.snapshot(appContext)
        val fallbackStepGoal = MoveStateStore.fallbackStepGoal(appContext)
        val samsungGoals = readSamsungGoals(nowDate)
        return Reading(
            steps = steps,
            stepGoal = samsungGoals.stepGoal ?: fallbackStepGoal,
            movements = snapshot.movements,
            movementGoal = snapshot.movementGoal,
            wakeMinutes = samsungGoals.wakeMinutes,
            bedtimeMinutes = samsungGoals.bedtimeMinutes,
            usesSamsungStepGoal = samsungGoals.stepGoal != null,
            usesSamsungSleepGoal =
                samsungGoals.wakeMinutes != null && samsungGoals.bedtimeMinutes != null,
        )
    }

    private data class SamsungGoals(
        val stepGoal: Int? = null,
        val wakeMinutes: Int? = null,
        val bedtimeMinutes: Int? = null,
    )

    private suspend fun readSamsungGoals(today: LocalDate): SamsungGoals {
        val store = try {
            HealthDataService.getStore(appContext)
        } catch (error: Exception) {
            if (isKnownSamsungUnavailable(error)) return SamsungGoals()
            throw TargetReadException(error.message, error)
        }
        val granted = try {
            store.getGrantedPermissions(samsungGoalPermissions)
        } catch (error: Exception) {
            if (isKnownSamsungUnavailable(error)) return SamsungGoals()
            throw TargetReadException(error.message, error)
        }

        val stepGoal = if (granted.contains(samsungStepGoalPermission)) {
            try {
                readSamsungStepGoal(store, today)
            } catch (error: Exception) {
                if (isKnownSamsungUnavailable(error)) null
                else throw TargetReadException(error.message, error)
            }
        } else {
            null
        }
        val sleepGoal = if (granted.contains(samsungSleepGoalPermission)) {
            try {
                readSamsungSleepGoal(store, today)
            } catch (error: Exception) {
                if (isKnownSamsungUnavailable(error)) null
                else throw TargetReadException(error.message, error)
            }
        } else {
            null
        }
        return SamsungGoals(
            stepGoal = stepGoal,
            wakeMinutes = sleepGoal?.second?.let(::minutesOfDay),
            bedtimeMinutes = sleepGoal?.first?.let(::minutesOfDay),
        )
    }

    private suspend fun readSamsungStepGoal(
        store: HealthDataStore,
        today: LocalDate,
    ): Int? {
        val request = DataType.StepsGoalType.LAST.requestBuilder
            .setLocalDateFilter(LocalDateFilter.of(today, today.plusDays(1)))
            .build()
        return store.aggregateData(request).dataList
            .lastOrNull()?.value?.takeIf { it > 0 }
    }

    private suspend fun readSamsungSleepGoal(
        store: HealthDataStore,
        today: LocalDate,
    ): Pair<LocalTime, LocalTime>? {
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
        val wake = store.aggregateData(wakeRequest).dataList
            .firstOrNull()?.value ?: return null
        return bedtime to wake
    }

    private fun minutesOfDay(time: LocalTime): Int = time.hour * 60 + time.minute

    private fun isKnownSamsungUnavailable(error: Throwable): Boolean {
        val healthError = error as? HealthDataException ?: return false
        return when (healthError) {
            is AuthorizationException -> healthError.errorCode == ErrorCode.ERR_NO_USER_PERMISSION ||
                healthError.errorCode == ErrorCode.ERR_ACCESS_CONTROL ||
                healthError.errorCode == ErrorCode.ERR_INVALID_PLATFORM_SIGNATURE ||
                healthError.errorCode == ErrorCode.ERR_UNSUPPORTED_OPERATION ||
                healthError.errorCode == ErrorCode.ERR_CHILD_ACCOUNT_ACCESS
            is ResolvablePlatformException -> healthError.errorCode == ErrorCode.ERR_PLATFORM_NOT_INSTALLED ||
                healthError.errorCode == ErrorCode.ERR_OLD_VERSION_PLATFORM ||
                healthError.errorCode == ErrorCode.ERR_PLATFORM_DISABLED ||
                healthError.errorCode == ErrorCode.ERR_PLATFORM_NOT_INITIALIZED
            else -> false
        }
    }
}
