package dev.embedded_devtools

import android.content.Context
import android.content.Intent
import android.os.Build
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class EmbeddedDevToolsPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "embedded_devtools")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startKeepAlive" -> {
                val intent = Intent(context, KeepAliveService::class.java)
                intent.putExtra("port", call.argument<Int>("port") ?: 0)
                try {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        context.startForegroundService(intent)
                    } else {
                        // No cached-app freezer before Android 12; a plain
                        // service is enough of a keep-alive hint.
                        context.startService(intent)
                    }
                    result.success(true)
                } catch (e: Exception) {
                    result.error("keep_alive_failed", e.message, null)
                }
            }
            "stopKeepAlive" -> {
                context.stopService(Intent(context, KeepAliveService::class.java))
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }
}
