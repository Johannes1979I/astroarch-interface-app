package com.zarletti.osservatorio.astroarch_interface

import android.content.Intent
import android.net.Uri
import android.provider.Settings
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private lateinit var gamepad: GamepadInput

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        gamepad = GamepadInput(this)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        EventChannel(messenger, "astroarch/gamepad/events").setStreamHandler(gamepad)
        MethodChannel(messenger, "astroarch/gamepad").setMethodCallHandler { call, result ->
            when (call.method) {
                // Il telecomando funziona solo a schermo acceso.
                "keepScreenOn" -> {
                    if (call.arguments == true) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    }
                    result.success(null)
                }
                // --- Telecomando associato (in background) ---
                "remoteStatus" -> result.success(remoteStatus())
                "remoteAssociate" -> {
                    RemoteSession.associate(applicationContext,
                        call.argument<String>("baseUrl") ?: "",
                        call.argument<String>("token") ?: "",
                        call.argument<String>("label") ?: "")
                    applyRemoteOptions(call.arguments as? Map<*, *>)
                    result.success(remoteStatus())
                }
                "remoteDissociate" -> {
                    RemoteSession.dissociate(applicationContext)
                    result.success(remoteStatus())
                }
                "remoteOptions" -> {
                    applyRemoteOptions(call.arguments as? Map<*, *>)
                    result.success(null)
                }
                "remoteScreenOpen" -> {
                    RemoteSession.screenOpen = call.arguments == true
                    result.success(null)
                }
                "openAccessibilitySettings" -> {
                    startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                    result.success(null)
                }
                "openAppSettings" -> {
                    startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                        Uri.fromParts("package", packageName, null)))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun remoteStatus(): Map<String, Any?> = mapOf(
        "serviceEnabled" to RemoteSession.serviceEnabled(this),
        "associated" to RemoteSession.associated,
        "label" to RemoteSession.label,
        "lastError" to RemoteSession.lastError,
        "lastKey" to RemoteSession.lastKey,
    )

    private fun applyRemoteOptions(args: Map<*, *>?) {
        if (args == null) return
        (args["mode"] as? String)?.let { RemoteSession.mode = it }
        (args["invertNS"] as? Boolean)?.let { RemoteSession.invertNS = it }
        (args["invertEW"] as? Boolean)?.let { RemoteSession.invertEW = it }
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean =
        (::gamepad.isInitialized && gamepad.onKey(event)) || super.dispatchKeyEvent(event)

    override fun dispatchGenericMotionEvent(event: MotionEvent): Boolean =
        (::gamepad.isInitialized && gamepad.onMotion(event)) || super.dispatchGenericMotionEvent(event)

    override fun onResume() {
        super.onResume()
        RemoteSession.activityResumed = true
    }

    override fun onPause() {
        RemoteSession.activityResumed = false
        if (::gamepad.isInitialized) gamepad.releaseAll()
        super.onPause()
    }
}
