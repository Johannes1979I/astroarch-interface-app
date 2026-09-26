package com.zarletti.osservatorio.astroarch_interface

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings

/**
 * Telecomando "associato": il controller muove la montatura anche fuori dalla
 * schermata Telecomando e con altre app aperte.
 *
 * I tasti arrivano da [RemoteAccessibilityService], che gira nello stesso
 * processo dell'app: questo oggetto e' il punto di incontro fra servizio,
 * Activity e Dart. Tutto lo stato vive solo in memoria: se Android uccide il
 * processo, al riavvio il telecomando NON e' associato, ed e' il default
 * sicuro.
 */
object RemoteSession {
    private const val CHANNEL = "astroarch_remote"
    private const val NOTIFICATION_ID = 7624

    @Volatile var slew: NativeSlew? = null
        private set
    @Volatile var label: String = ""
        private set
    /** "dpad": croce = direzioni, B = STOP. "buttons": Y/A/X/B = N/S/O/E, RB = STOP. */
    @Volatile var mode: String = "dpad"
    @Volatile var invertNS = false
    @Volatile var invertEW = false
    @Volatile var lastError: String? = null
    /** Ultimo tasto del controller visto dal servizio: diagnostica per la schermata. */
    @Volatile var lastKey: String? = null

    // La schermata Telecomando, quando e' davvero in primo piano, gestisce lei
    // il controller (anche la levetta): il servizio allora si fa da parte.
    @Volatile var screenOpen = false
    @Volatile var activityResumed = false

    val associated: Boolean get() = slew != null
    val screenHandlesInput: Boolean get() = screenOpen && activityResumed

    fun associate(context: Context, baseUrl: String, token: String, label: String) {
        slew?.shutdown()
        lastError = null
        this.label = label
        slew = NativeSlew(baseUrl, token) { lastError = it }
        showNotification(context)
    }

    fun dissociate(context: Context) {
        slew?.shutdown()
        slew = null
        cancelNotification(context)
    }

    fun serviceEnabled(context: Context): Boolean {
        val me = ComponentName(context, RemoteAccessibilityService::class.java).flattenToString()
        val enabled = Settings.Secure.getString(
            context.contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES) ?: return false
        return enabled.split(':').any { it.equals(me, ignoreCase = true) }
    }

    private fun showNotification(context: Context) {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(NotificationChannel(
                CHANNEL, "Telecomando montatura", NotificationManager.IMPORTANCE_LOW))
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        val stop = PendingIntent.getBroadcast(context, 1,
            Intent(context, RemoteStopReceiver::class.java), flags)
        val open = PendingIntent.getActivity(context, 2,
            Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP), flags)
        @Suppress("DEPRECATION")
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL)
        } else {
            Notification.Builder(context)
        }
        @Suppress("DEPRECATION")
        val n = builder
            .setSmallIcon(R.drawable.ic_stat_remote)
            .setContentTitle("Telecomando attivo")
            .setContentText(label)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(open)
            .addAction(0, "Disattiva", stop)
            .build()
        try {
            nm.notify(NOTIFICATION_ID, n)
        } catch (e: SecurityException) {
            // Notifiche non permesse: il telecomando funziona lo stesso, lo
            // stato si vede e si cambia dalla schermata Telecomando.
        }
    }

    private fun cancelNotification(context: Context) {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.cancel(NOTIFICATION_ID)
    }
}

/** Pulsante "Disattiva" della notifica. */
class RemoteStopReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        RemoteSession.dissociate(context.applicationContext)
    }
}
