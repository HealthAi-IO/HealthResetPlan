package io.healthresetplan.health_reset_plan

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.ContentValues
import android.os.Build
import android.provider.MediaStore

class MainActivity : FlutterActivity() {
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
