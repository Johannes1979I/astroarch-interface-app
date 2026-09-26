package com.zarletti.osservatorio.astroarch_interface

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.os.Build
import android.view.InputDevice
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.accessibility.AccessibilityEvent

/**
 * Riceve il controller anche quando l'app non e' in primo piano.
 *
 * Android consegna l'input solo all'app in primo piano; un servizio di
 * accessibilita' lo vede prima di lei, ed e' l'unico modo ufficiale di
 * riceverlo in background. Il servizio:
 *  - non legge il contenuto dello schermo (canRetrieveWindowContent=false);
 *  - guarda solo l'input che viene da un controller di gioco;
 *  - lo trattiene SOLO se il telecomando e' associato, altrimenti lo lascia
 *    passare intatto;
 *  - con la schermata Telecomando in primo piano si fa da parte, perche' li'
 *    comanda la schermata.
 *
 * Due canali:
 *  - TASTI (onKeyEvent, ogni versione di Android): A/B/X/Y, dorsali, e la
 *    croce solo sui telefoni che la presentano come tasti;
 *  - ASSI (onMotionEvent, Android 14+): la croce dei controller Xbox, che
 *    Android presenta come asse "HAT", e la levetta sinistra. Vanno chiesti
 *    esplicitamente con setMotionEventSources(SOURCE_JOYSTICK), e finche' sono
 *    chiesti le altre app non li ricevono piu': per questo si chiedono solo
 *    mentre il telecomando e' associato e la schermata non e' in primo piano.
 */
class RemoteAccessibilityService : AccessibilityService() {
    private val keyDirs = mutableSetOf<String>()
    private val axisDirs = mutableSetOf<String>()
    // Dopo lo STOP le direzioni sono ignorate finche' non si rilascia tutto.
    private var stopLatched = false
    private var capturingAxes = false

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}
    override fun onInterrupt() {}

    override fun onServiceConnected() {
        super.onServiceConnected()
        RemoteSession.service = this
        updateCapture()
    }

    override fun onUnbind(intent: Intent?): Boolean {
        // Servizio disattivato dalle impostazioni: nessun movimento orfano.
        RemoteSession.service = null
        RemoteSession.slew?.stopAll()
        return super.onUnbind(intent)
    }

    /** Chiamato da RemoteSession quando cambia associazione o primo piano. */
    fun updateCapture() {
        val want = RemoteSession.associated && !RemoteSession.screenHandlesInput
        if (!want) forget()
        setAxisCapture(want)
    }

    private fun setAxisCapture(on: Boolean) {
        // Prima di Android 14 gli assi non arrivano ai servizi: restano i tasti.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return
        if (on == capturingAxes) return
        val info = serviceInfo ?: return
        info.motionEventSources = if (on) InputDevice.SOURCE_JOYSTICK else 0
        serviceInfo = info
        capturingAxes = on
    }

    override fun onMotionEvent(event: MotionEvent) {
        if (event.action != MotionEvent.ACTION_MOVE) return
        val hatX = event.getAxisValue(MotionEvent.AXIS_HAT_X)
        val hatY = event.getAxisValue(MotionEvent.AXIS_HAT_Y)
        val stickX = event.getAxisValue(MotionEvent.AXIS_X)
        val stickY = event.getAxisValue(MotionEvent.AXIS_Y)
        val dirs = mutableSetOf<String>()
        if (hatY < -0.5f || stickY < -STICK) dirs.add("N")
        if (hatY > 0.5f || stickY > STICK) dirs.add("S")
        if (hatX < -0.5f || stickX < -STICK) dirs.add("W")
        if (hatX > 0.5f || stickX > STICK) dirs.add("E")
        if (dirs.isNotEmpty()) {
            RemoteSession.lastKey = (if (hatX != 0f || hatY != 0f) "CROCE (asse) " else "LEVETTA ") +
                dirs.joinToString("")
        }
        if (RemoteSession.slew == null || RemoteSession.screenHandlesInput) return
        if (dirs == axisDirs) return
        axisDirs.clear()
        axisDirs.addAll(dirs)
        apply()
    }

    override fun onKeyEvent(event: KeyEvent): Boolean {
        if (!fromGamepad(event)) return false
        val name = KEY_NAMES[event.keyCode] ?: return false
        if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
            RemoteSession.lastKey = name
        }
        val slew = RemoteSession.slew
        if (slew == null || RemoteSession.screenHandlesInput) {
            // Non tocca a noi: dimentica i tasti tenuti, altrimenti al ritorno
            // una direzione rilasciata altrove resterebbe "premuta".
            forget()
            return false
        }

        val buttonsMode = RemoteSession.mode == "buttons"
        val dir = if (buttonsMode) BUTTON_DIRS[name] else DPAD_DIRS[name]
        val isStop = name == (if (buttonsMode) "RB" else "B")
        if (dir == null && !isStop) return false   // tasto che non ci riguarda
        if (event.repeatCount > 0) return true

        val down = event.action == KeyEvent.ACTION_DOWN
        if (isStop) {
            if (down) {
                stopLatched = true
                slew.abort()
            }
            return true
        }
        if (down) keyDirs.add(dir!!) else keyDirs.remove(dir!!)
        apply()
        return true
    }

    private fun apply() {
        val slew = RemoteSession.slew ?: return
        val pressed = keyDirs + axisDirs
        if (stopLatched) {
            if (pressed.isEmpty()) stopLatched = false
            return
        }
        var ns = axis(pressed, "N", "S")
        var we = axis(pressed, "W", "E")
        if (RemoteSession.invertNS && ns != null) ns = if (ns == "N") "S" else "N"
        if (RemoteSession.invertEW && we != null) we = if (we == "W") "E" else "W"
        slew.set(ns, we)
    }

    private fun forget() {
        keyDirs.clear()
        axisDirs.clear()
        stopLatched = false
    }

    private fun axis(p: Set<String>, a: String, b: String): String? = when {
        a in p && b !in p -> a
        b in p && a !in p -> b
        else -> null
    }

    private fun fromGamepad(event: KeyEvent): Boolean {
        val sources = InputDevice.getDevice(event.deviceId)?.sources ?: event.source
        return (sources and InputDevice.SOURCE_GAMEPAD) == InputDevice.SOURCE_GAMEPAD ||
            (sources and InputDevice.SOURCE_JOYSTICK) == InputDevice.SOURCE_JOYSTICK
    }

    companion object {
        /** Oltre meta' corsa la levetta conta come direzione: sotto, e' rumore. */
        private const val STICK = 0.5f

        private val KEY_NAMES = mapOf(
            KeyEvent.KEYCODE_DPAD_UP to "UP",
            KeyEvent.KEYCODE_DPAD_DOWN to "DOWN",
            KeyEvent.KEYCODE_DPAD_LEFT to "LEFT",
            KeyEvent.KEYCODE_DPAD_RIGHT to "RIGHT",
            KeyEvent.KEYCODE_BUTTON_A to "A",
            KeyEvent.KEYCODE_BUTTON_B to "B",
            KeyEvent.KEYCODE_BUTTON_X to "X",
            KeyEvent.KEYCODE_BUTTON_Y to "Y",
            KeyEvent.KEYCODE_BUTTON_L1 to "LB",
            KeyEvent.KEYCODE_BUTTON_R1 to "RB",
        )
        private val DPAD_DIRS = mapOf("UP" to "N", "DOWN" to "S", "LEFT" to "W", "RIGHT" to "E")
        private val BUTTON_DIRS = mapOf("Y" to "N", "A" to "S", "X" to "W", "B" to "E")
    }
}
