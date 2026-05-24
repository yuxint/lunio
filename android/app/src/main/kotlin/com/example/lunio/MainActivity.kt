package com.example.lunio

import android.app.Activity
import android.content.Intent
import java.io.File
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pendingPickJsonResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "lunio/native_files",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "shareFile" -> shareFile(call.argument("path"), result)
                "pickJsonFile" -> pickJsonFile(result)
                else -> result.notImplemented()
            }
        }
    }

    private fun shareFile(path: String?, result: MethodChannel.Result) {
        if (path == null) {
            result.error("invalid_arguments", "Missing file path", null)
            return
        }
        val file = File(path)
        if (!file.exists()) {
            result.error("file_not_found", "Backup file not found", null)
            return
        }
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = "application/json"
            putExtra(Intent.EXTRA_SUBJECT, file.name)
            putExtra(Intent.EXTRA_TEXT, file.readText())
        }
        startActivity(Intent.createChooser(intent, "分享备份文件"))
        result.success(null)
    }

    private fun pickJsonFile(result: MethodChannel.Result) {
        if (pendingPickJsonResult != null) {
            result.error("picker_active", "A file picker is already active", null)
            return
        }
        pendingPickJsonResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(
                Intent.EXTRA_MIME_TYPES,
                arrayOf("application/json", "text/plain"),
            )
        }
        startActivityForResult(intent, PICK_JSON_REQUEST_CODE)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != PICK_JSON_REQUEST_CODE) {
            return
        }
        val result = pendingPickJsonResult ?: return
        pendingPickJsonResult = null
        if (resultCode != Activity.RESULT_OK) {
            result.success(null)
            return
        }
        val uri = data?.data
        if (uri == null) {
            result.success(null)
            return
        }
        try {
            val text = contentResolver.openInputStream(uri)?.bufferedReader()?.use {
                it.readText()
            }
            result.success(text)
        } catch (error: Exception) {
            result.error("read_failed", error.localizedMessage, null)
        }
    }

    companion object {
        private const val PICK_JSON_REQUEST_CODE = 4101
    }
}
