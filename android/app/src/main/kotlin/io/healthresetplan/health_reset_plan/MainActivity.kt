package io.healthresetplan.health_reset_plan

import android.util.Log
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.PermissionController
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.HeartRateRecord
import androidx.health.connect.client.records.SleepSessionRecord
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.request.AggregateRequest
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import androidx.activity.ComponentActivity
import androidx.activity.result.ActivityResultLauncher
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.time.Instant
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

class MainActivity : FlutterFragmentActivity() {
  private val channelName = "health_sync_bridge"
  private val coroutineScope = CoroutineScope(Dispatchers.Main)
  private var pendingAccessResult: MethodChannel.Result? = null
  private var healthClient: HealthConnectClient? = null
  private val healthPermissions = setOf(
    HealthPermission.getReadPermission(StepsRecord::class),
    HealthPermission.getReadPermission(HeartRateRecord::class),
    HealthPermission.getReadPermission(SleepSessionRecord::class),
  )

  private val healthPermissionStrings = setOf(
    HealthPermission.getReadPermission(StepsRecord::class),
    HealthPermission.getReadPermission(HeartRateRecord::class),
    HealthPermission.getReadPermission(SleepSessionRecord::class),
  )
  private lateinit var permissionLauncher: ActivityResultLauncher<Set<String>>

  override fun onCreate(savedInstanceState: android.os.Bundle?) {
    super.onCreate(savedInstanceState)
    permissionLauncher = registerForActivityResult(
      PermissionController.createRequestPermissionResultContract()
    ) { granted ->
      pendingAccessResult?.success(granted.containsAll(healthPermissionStrings))
      pendingAccessResult = null
    }
  }

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)

    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
      when (call.method) {
        "isAvailable" -> result.success(HealthConnectClient.getSdkStatus(this) == HealthConnectClient.SDK_AVAILABLE)
        "requestAccess" -> requestAccess(result)
        "sync" -> coroutineScope.launch {
          try {
            result.success(readSnapshot())
          } catch (e: Exception) {
            Log.e(channelName, "sync failed", e)
            result.error("SYNC_FAILED", e.message, null)
          }
        }
        else -> result.notImplemented()
      }
    }
  }

  private fun requestAccess(result: MethodChannel.Result) {
    if (HealthConnectClient.getSdkStatus(this) != HealthConnectClient.SDK_AVAILABLE) {
      result.success(false)
      return
    }
    pendingAccessResult = result
    permissionLauncher.launch(healthPermissionStrings)
  }

  private fun client(): HealthConnectClient {
    val existing = healthClient
    if (existing != null) return existing
    return HealthConnectClient.getOrCreate(this).also { healthClient = it }
  }

  private suspend fun readSnapshot(): Map<String, Any?> {
    val now = Instant.now()
    val zone = ZoneId.systemDefault()
    val startOfDay = now.atZone(zone).toLocalDate().atStartOfDay(zone).toInstant()
    val yesterday = now.minus(1, ChronoUnit.DAYS)

    val steps = readSteps(startOfDay, now)
    val heartRate = readHeartRate(yesterday, now)
    val sleepHours = readSleepHours(yesterday, now)

    return mapOf(
      "steps" to steps,
      "heartRateBpm" to heartRate,
      "sleepHours" to sleepHours,
      "recordedAt" to now.toEpochMilli(),
    )
  }

  private suspend fun readSteps(start: Instant, end: Instant): Int? {
    val response = client().aggregate(
      AggregateRequest(
        metrics = setOf(StepsRecord.COUNT_TOTAL),
        timeRangeFilter = TimeRangeFilter.between(start, end),
      )
    )
    val total = response[StepsRecord.COUNT_TOTAL]?.toInt() ?: 0
    return if (total > 0) total else null
  }

  private suspend fun readHeartRate(start: Instant, end: Instant): Int? {
    val response = client().readRecords(
      ReadRecordsRequest(
        HeartRateRecord::class,
        timeRangeFilter = TimeRangeFilter.between(start, end),
      )
    )
    val latest = response.records.maxByOrNull { it.endTime.toEpochMilli() } ?: return null
    return latest.samples.maxByOrNull { it.time.toEpochMilli() }?.beatsPerMinute?.toInt()
  }

  private suspend fun readSleepHours(start: Instant, end: Instant): Double? {
    val response = client().readRecords(
      ReadRecordsRequest(
        SleepSessionRecord::class,
        timeRangeFilter = TimeRangeFilter.between(start, end),
      )
    )
    val totalMinutes = response.records.sumOf {
      ChronoUnit.MINUTES.between(it.startTime, it.endTime).toInt()
    }
    return if (totalMinutes > 0) totalMinutes / 60.0 else null
  }
}
