package io.healthresetplan.health_reset_plan

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.ContentValues
import android.os.Build
import android.provider.MediaStore
import android.Manifest
import android.content.pm.PackageManager
import android.os.Environment
import android.media.MediaScannerConnection
import java.io.File

class MainActivity : FlutterActivity() {
    private var pendingSave: Pair<ByteArray, MethodChannel.Result>? = null

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != 901) return
        val pending = pendingSave ?: return
        pendingSave = null
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) saveLegacy(pending.first, pending.second)
        else pending.second.error("permission_denied", "未允许保存到相册，打卡记录已保留", null)
    }

    private fun saveLegacy(bytes: ByteArray, result: MethodChannel.Result) {
        var file: File? = null
        try {
            val directory = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES), "HealthResetPlan")
            if (!directory.exists() && !directory.mkdirs()) error("无法创建图片目录")
            file = File(directory, "routine-${System.currentTimeMillis()}.png")
            file.writeBytes(bytes)
            MediaScannerConnection.scanFile(this, arrayOf(file.absolutePath), arrayOf("image/png"), null)
            result.success(null)
        } catch (ex: Exception) {
            file?.delete()
            result.error("save_failed", "图片保存失败，打卡记录已保留", null)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "health_reset_plan/gallery")
            .setMethodCallHandler { call, result ->
                if (call.method != "save") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val bytes = call.arguments as? ByteArray
                if (bytes == null) {
                    result.error("invalid", "图片内容无效", null)
                    return@setMethodCallHandler
                }
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                    if (pendingSave != null) result.error("busy", "图片正在保存", null)
                    else if (checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED) saveLegacy(bytes, result)
                    else {
                        pendingSave = Pair(bytes, result)
                        requestPermissions(arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE), 901)
                    }
                    return@setMethodCallHandler
                }
                val values = ContentValues().apply {
                    put(MediaStore.Images.Media.DISPLAY_NAME, "routine-${System.currentTimeMillis()}.png")
                    put(MediaStore.Images.Media.MIME_TYPE, "image/png")
                    put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/HealthResetPlan")
                    put(MediaStore.Images.Media.IS_PENDING, 1)
                }
                var uri: android.net.Uri? = null
                try {
                    uri = contentResolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
                        ?: error("无法创建图片")
                    val output = contentResolver.openOutputStream(uri) ?: error("无法写入图片")
                    output.use { it.write(bytes) }
                    values.clear()
                    values.put(MediaStore.Images.Media.IS_PENDING, 0)
                    contentResolver.update(uri, values, null, null)
                    result.success(null)
                } catch (ex: Exception) {
                    uri?.let { contentResolver.delete(it, null, null) }
                    result.error("save_failed", "图片保存失败", null)
                }
            }
    }
}
