package com.zarletti.osservatorio.astroarch_interface

import android.accessibilityservice.AccessibilityService
import android.view.InputDevice
import android.view.KeyEvent
import android.view.accessibility.AccessibilityEvent

/**
 * Riceve i tasti del controller anche quando l'app non e' in primo piano.
 *
 * Android consegna i tasti solo all'app in primo piano; un servizio di
 * accessibilita' con `flagRequestFilterKeyEvents` li vede prima di lei, ed e'
 * l'unico modo ufficiale di riceverli in background. Il servizio:
 *  - non legge il contenuto dello schermo (canRetrieveWindowContent=false);
 *  - guarda solo i tasti che vengono da un controller di gioco;
 *  - li trattiene SOLO se il telecomando e' associato, altrimenti li lascia
 *    passare intatti;
 *  - con la schermata Telecomando in primo piano si fa da parte, perche' li'
 *    comanda la schermata (che usa anche la levetta).
 *
 * La levetta non arriva mai qui: e' un asse analogico, e ai servizi di
 * accessibilita' arrivano solo i tasti.
 */
class RemoteAccessibilityService : AccessibilityService() {
    private val pressed = mutableSetOf<String>()
    // Dopo lo STOP le direzioni sono ignorate finche' non si rilascia tutto.
    private var stopLatched = false

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}
    override fun onInterrupt() {}

    override fun onUnbind(intent: android.content.Intent?): Boolean {
        // Servizio disattivato dalle impostazioni: nessun movimento orfano.
        RemoteSession.slew?.stopAll()
        return super.onUnbind(intent)
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
            pressed.clear()
            stopLatched = false
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
                pressed.clear()
                slew.abort()
            }
            return true
        }
        if (down) pressed.add(dir!!) else pressed.remove(dir!!)
        if (stopLatched) {
            if (pressed.isEmpty()) stopLatched = false
            return true
        }
        var ns = axis(pressed, "N", "S")
        var we = axis(pressed, "W", "E")
        if (RemoteSession.invertNS && ns != null) ns = if (ns == "N") "S" else "N"
        if (RemoteSession.invertEW && we != null) we = if (we == "W") "E" else "W"
        slew.set(ns, we)
        return true
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
