package com.zarletti.osservatorio.astroarch_interface

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
                else -> result.notImplemented()
            }
        }
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean =
        (::gamepad.isInitialized && gamepad.onKey(event)) || super.dispatchKeyEvent(event)

    override fun dispatchGenericMotionEvent(event: MotionEvent): Boolean =
        (::gamepad.isInitialized && gamepad.onMotion(event)) || super.dispatchGenericMotionEvent(event)

    override fun onPause() {
        if (::gamepad.isInitialized) gamepad.releaseAll()
        super.onPause()
    }
}
