package com.zarletti.osservatorio.astroarch_interface

import android.content.Context
import android.hardware.input.InputManager
import android.os.Handler
import android.os.Looper
import android.view.InputDevice
import android.view.KeyEvent
import android.view.MotionEvent
import io.flutter.plugin.common.EventChannel

/**
 * Controller di gioco Bluetooth (Xbox e simili) per il telecomando della montatura.
 *
 * Android non consegna i controller a Flutter come tasti: la croce di un
 * controller Xbox arriva come asse "HAT", la levetta come assi X/Y. Qui li
 * riduciamo a quattro direzioni piu' l'elenco dei tasti premuti, e mandiamo a
 * Dart lo stato completo solo quando cambia.
 *
 * Gli eventi vengono intercettati SOLO mentre Dart ascolta (schermata
 * Telecomando aperta): nel resto dell'app il controller si comporta come
 * sempre, e il tasto B non viene piu' tradotto in "indietro" solo li'.
 */
class GamepadInput(context: Context) : EventChannel.StreamHandler, InputManager.InputDeviceListener {
    private val inputManager = context.getSystemService(Context.INPUT_SERVICE) as InputManager
    private val main = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null

    private var hatX = 0f
    private var hatY = 0f
    private var stickX = 0f
    private var stickY = 0f
    private val dpadKeys = mutableSetOf<Int>()
    private val buttons = sortedSetOf<String>()
    private var lastSent: Map<String, Any>? = null

    val listening: Boolean get() = sink != null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
        inputManager.registerInputDeviceListener(this, main)
        lastSent = null
        emitState()
    }

    override fun onCancel(arguments: Any?) {
        inputManager.unregisterInputDeviceListener(this)
        sink = null
        clear()
    }

    fun onKey(event: KeyEvent): Boolean {
        if (!listening || !isGamepad(event.source)) return false
        val code = event.keyCode
        val down = event.action == KeyEvent.ACTION_DOWN
        val name = BUTTONS[code]
        when {
            code in DPAD -> if (down) dpadKeys.add(code) else dpadKeys.remove(code)
            name != null -> if (down) buttons.add(name) else buttons.remove(name)
            else -> return false
        }
        emitState()
        return true
    }

    fun onMotion(event: MotionEvent): Boolean {
        if (!listening || !isGamepad(event.source) || event.action != MotionEvent.ACTION_MOVE) return false
        hatX = event.getAxisValue(MotionEvent.AXIS_HAT_X)
        hatY = event.getAxisValue(MotionEvent.AXIS_HAT_Y)
        stickX = event.getAxisValue(MotionEvent.AXIS_X)
        stickY = event.getAxisValue(MotionEvent.AXIS_Y)
        emitState()
        return true
    }

    /** L'app va in secondo piano o il controller sparisce: niente tasti premuti. */
    fun releaseAll() {
        clear()
        emitState()
    }

    fun connectedNames(): List<String> = InputDevice.getDeviceIds().toList()
        .mapNotNull { InputDevice.getDevice(it) }
        .filter { !it.isVirtual && isGamepad(it.sources) }
        .map { it.name }
        .distinct()

    override fun onInputDeviceAdded(deviceId: Int) = emitState()
    override fun onInputDeviceChanged(deviceId: Int) = emitState()
    override fun onInputDeviceRemoved(deviceId: Int) = releaseAll()

    private fun clear() {
        hatX = 0f; hatY = 0f; stickX = 0f; stickY = 0f
        dpadKeys.clear()
        buttons.clear()
    }

    private fun emitState() {
        val s = sink ?: return
        val state = mapOf(
            "up" to (hatY < -0.5f || stickY < -STICK || KeyEvent.KEYCODE_DPAD_UP in dpadKeys),
            "down" to (hatY > 0.5f || stickY > STICK || KeyEvent.KEYCODE_DPAD_DOWN in dpadKeys),
            "left" to (hatX < -0.5f || stickX < -STICK || KeyEvent.KEYCODE_DPAD_LEFT in dpadKeys),
            "right" to (hatX > 0.5f || stickX > STICK || KeyEvent.KEYCODE_DPAD_RIGHT in dpadKeys),
            "buttons" to buttons.toList(),
            "devices" to connectedNames(),
        )
        if (state == lastSent) return
        lastSent = state
        s.success(state)
    }

    private fun isGamepad(sources: Int): Boolean =
        sources and InputDevice.SOURCE_GAMEPAD == InputDevice.SOURCE_GAMEPAD ||
            sources and InputDevice.SOURCE_JOYSTICK == InputDevice.SOURCE_JOYSTICK

    companion object {
        /** Oltre meta' corsa la levetta conta come direzione: sotto, e' rumore. */
        private const val STICK = 0.5f

        private val DPAD = setOf(
            KeyEvent.KEYCODE_DPAD_UP, KeyEvent.KEYCODE_DPAD_DOWN,
            KeyEvent.KEYCODE_DPAD_LEFT, KeyEvent.KEYCODE_DPAD_RIGHT,
        )

        private val BUTTONS = mapOf(
            KeyEvent.KEYCODE_BUTTON_A to "A",
            KeyEvent.KEYCODE_BUTTON_B to "B",
            KeyEvent.KEYCODE_BUTTON_X to "X",
            KeyEvent.KEYCODE_BUTTON_Y to "Y",
            KeyEvent.KEYCODE_BUTTON_L1 to "LB",
            KeyEvent.KEYCODE_BUTTON_R1 to "RB",
            KeyEvent.KEYCODE_BUTTON_START to "START",
            KeyEvent.KEYCODE_BUTTON_SELECT to "SELECT",
        )
    }
}
