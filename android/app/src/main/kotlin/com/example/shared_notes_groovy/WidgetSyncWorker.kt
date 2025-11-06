package com.example.shared_notes_groovy

import android.app.NotificationChannel
import android.app.NotificationManager
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.graphics.Color
import android.net.Uri
import android.os.Build
import android.widget.RemoteViews
import androidx.core.app.NotificationCompat
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import org.json.JSONObject
import java.net.URL

class WidgetSyncWorker(appContext: Context, params: WorkerParameters) : CoroutineWorker(appContext, params) {
    override suspend fun doWork(): Result {
        val context = applicationContext
        try {
            val updatesUrl = URL("https://shared-notes-app-2a464-default-rtdb.firebaseio.com/notes/updates.json")
            val widgetUrl = URL("https://shared-notes-app-2a464-default-rtdb.firebaseio.com/notes/widget.json")

            val prefs = context.getSharedPreferences("widget_sync", Context.MODE_PRIVATE)
            val lastWidgetTs = prefs.getLong("last_widget_ts", 0L)
            val lastNotesTs = prefs.getLong("last_notes_ts", 0L)

            // Check note updates for notification
            try {
                val t = updatesUrl.readText()
                val obj = JSONObject(t)
                val ts = obj.optLong("updated_at", 0L)
                if (ts > lastNotesTs) {
                    val title = obj.optString("title", "Note updated")
                    showNotification(context, "Note updated: $title")
                    prefs.edit().putLong("last_notes_ts", ts).apply()
                }
            } catch (_: Exception) {}

            // Update widget if newer content
            try {
                val w = widgetUrl.readText()
                val obj = JSONObject(w)
                val ts = obj.optLong("updated_at", 0L)
                if (ts > lastWidgetTs) {
                    val displayText = obj.optString("display_text", "No note content yet...")
                    val imagePath = obj.optString("image_path", "")
                    val views = RemoteViews(context.packageName, R.layout.note_widget_layout).apply {
                        setTextViewText(R.id.note_text, displayText)
                        if (imagePath.isNotEmpty()) {
                            try {
                                val uri = if (imagePath.startsWith("file://")) Uri.parse(imagePath) else Uri.parse("file://$imagePath")
                                setImageViewUri(R.id.note_image, uri)
                                setViewVisibility(R.id.note_image, android.view.View.VISIBLE)
                            } catch (_: Exception) {
                                setViewVisibility(R.id.note_image, android.view.View.GONE)
                            }
                        } else {
                            setViewVisibility(R.id.note_image, android.view.View.GONE)
                        }
                    }
                    val manager = AppWidgetManager.getInstance(context)
                    val component = ComponentName(context, NoteWidgetProvider::class.java)
                    val ids = manager.getAppWidgetIds(component)
                    manager.updateAppWidget(ids, views)
                    prefs.edit().putLong("last_widget_ts", ts).apply()
                }
            } catch (_: Exception) {}

            return Result.success()
        } catch (_: Exception) {
            return Result.retry()
        }
    }

    private fun showNotification(context: Context, message: String) {
        val channelId = "shared_notes_updates"
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            if (manager.getNotificationChannel(channelId) == null) {
                val ch = NotificationChannel(channelId, "Shared Notes", NotificationManager.IMPORTANCE_DEFAULT)
                ch.description = "Notifications for shared note updates"
                ch.enableLights(true)
                ch.lightColor = Color.BLUE
                manager.createNotificationChannel(ch)
            }
        }
        val notif = NotificationCompat.Builder(context, channelId)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Shared Notes")
            .setContentText(message)
            .setAutoCancel(true)
            .build()
        manager.notify(2001, notif)
    }
}

