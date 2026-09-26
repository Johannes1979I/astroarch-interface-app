package com.zarletti.osservatorio.astroarch_interface

import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit

/**
 * Movimenti manuali protetti, per il telecomando in background.
 *
 * E' la stessa logica di `lib/mount/slew_controller.dart`, rifatta in Kotlin
 * perche' con l'app in background il codice Dart puo' essere sospeso: qui
 * gira nel processo del servizio di accessibilita', che Android tiene vivo.
 *
 * Tutto (invii, conferme, retry) avviene su UN solo thread: l'ordine dei
 * comandi e' garantito per costruzione, un arresto non sorpassa mai la
 * partenza che lo precede.
 */
class NativeSlew(
    private val baseUrl: String,
    private val token: String,
    private val onError: (String) -> Unit,
) {
    private val exec = Executors.newSingleThreadScheduledExecutor()
    private val want = mutableMapOf<String, String?>("NS" to null, "WE" to null)
    // Direzione che il bridge potrebbe avere in corso: segnata PRIMA di
    // inviare la partenza, cosi' al rilascio l'arresto parte comunque.
    private val sent = mutableMapOf<String, String?>("NS" to null, "WE" to null)
    private var beat: ScheduledFuture<*>? = null
    private var failingSince = 0L

    fun set(ns: String?, we: String?) = exec.execute {
        want["NS"] = ns
        want["WE"] = we
        if (beat == null) {
            beat = exec.scheduleWithFixedDelay({ tick() }, HEARTBEAT_MS, HEARTBEAT_MS, TimeUnit.MILLISECONDS)
        }
        sync(false)
    }

    fun stopAll() = set(null, null)

    fun abort() = exec.execute {
        want["NS"] = null
        want["WE"] = null
        try {
            post("/api/mount/abort", JSONObject())
        } catch (e: Exception) {
            onError("STOP: ${e.message}")
        }
        sync(false)
    }

    /** Ferma tutto e libera il thread quando gli arresti sono consegnati. */
    fun shutdown() {
        stopAll()
        exec.schedule({ exec.shutdown() }, GIVE_UP_MS, TimeUnit.MILLISECONDS)
    }

    private fun tick() {
        sync(true)
        val settled = want.values.all { it == null } && sent.values.all { it == null }
        val givingUp = failingSince != 0L && System.currentTimeMillis() - failingSince > GIVE_UP_MS &&
            want.values.all { it == null }
        if (settled || givingUp) {
            // Se il bridge resta irraggiungibile, l'asse l'ha gia' fermato lui
            // allo scadere di TTL_MS: inutile insistere.
            if (givingUp) { sent["NS"] = null; sent["WE"] = null }
            beat?.cancel(false)
            beat = null
            failingSince = 0L
        }
    }

    private fun sync(isBeat: Boolean) {
        for (axis in listOf("NS", "WE")) {
            val w = want[axis]
            val s = sent[axis]
            try {
                when {
                    w != null && w != s -> { sent[axis] = w; slew(w, true) }
                    w == null && s != null -> { slew(s, false); sent[axis] = null }
                    w != null && isBeat -> slew(w, true)
                }
                failingSince = 0L
            } catch (e: Exception) {
                if (failingSince == 0L) failingSince = System.currentTimeMillis()
                onError(e.message ?: e.toString())
            }
        }
    }

    private fun slew(dir: String, active: Boolean) {
        post("/api/mount/slew", JSONObject()
            .put("direction", dir).put("active", active).put("ttl_ms", TTL_MS))
    }

    private fun post(path: String, body: JSONObject) {
        val c = URL(baseUrl.trimEnd('/') + path).openConnection() as HttpURLConnection
        try {
            c.requestMethod = "POST"
            c.connectTimeout = 2000
            c.readTimeout = 2000
            c.doOutput = true
            c.setRequestProperty("Authorization", "Bearer $token")
            c.setRequestProperty("Content-Type", "application/json")
            c.outputStream.use { it.write(body.toString().toByteArray()) }
            val code = c.responseCode
            if (code !in 200..299) throw RuntimeException("HTTP $code")
        } finally {
            c.disconnect()
        }
    }

    companion object {
        const val TTL_MS = 1000
        const val HEARTBEAT_MS = 250L
        const val GIVE_UP_MS = 5000L
    }
}
