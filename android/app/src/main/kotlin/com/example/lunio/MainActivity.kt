package com.example.lunio

import android.app.Activity
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pendingPickJsonResult: MethodChannel.Result? = null
    private var pendingExportJsonResult: MethodChannel.Result? = null
    private var pendingExportJsonContent: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "lunio/native_files",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "exportJsonFile" -> exportJsonFile(
                    call.argument("filename"),
                    call.argument("content"),
                    result,
                )
                "pickJsonFile" -> pickJsonFile(result)
                else -> result.notImplemented()
            }
        }
    }

    private fun exportJsonFile(
        filename: String?,
        content: String?,
        result: MethodChannel.Result,
    ) {
        if (filename == null || content == null) {
            result.error("invalid_arguments", "Missing backup filename or content", null)
            return
        }
        if (pendingExportJsonResult != null) {
            result.error("export_active", "A file export is already active", null)
            return
        }
        pendingExportJsonResult = result
        pendingExportJsonContent = content
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "application/json"
            putExtra(Intent.EXTRA_TITLE, filename)
        }
        startActivityForResult(intent, EXPORT_JSON_REQUEST_CODE)
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
        when (requestCode) {
            PICK_JSON_REQUEST_CODE -> handlePickJsonResult(resultCode, data)
            EXPORT_JSON_REQUEST_CODE -> handleExportJsonResult(resultCode, data)
        }
    }

    private fun handlePickJsonResult(resultCode: Int, data: Intent?) {
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

    private fun handleExportJsonResult(resultCode: Int, data: Intent?) {
        val result = pendingExportJsonResult ?: return
        val content = pendingExportJsonContent
        pendingExportJsonResult = null
        pendingExportJsonContent = null
        if (resultCode != Activity.RESULT_OK) {
            result.success(null)
            return
        }
        val uri = data?.data
        if (uri == null || content == null) {
            result.success(null)
            return
        }
        try {
            val outputStream = contentResolver.openOutputStream(uri)
            if (outputStream == null) {
                result.error("write_failed", "Unable to open backup file", null)
                return
            }
            outputStream.bufferedWriter().use {
                it.write(content)
            }
            result.success(null)
        } catch (error: Exception) {
            result.error("write_failed", error.localizedMessage, null)
        }
    }

    companion object {
        private const val PICK_JSON_REQUEST_CODE = 4101
        private const val EXPORT_JSON_REQUEST_CODE = 4102
    }
}
