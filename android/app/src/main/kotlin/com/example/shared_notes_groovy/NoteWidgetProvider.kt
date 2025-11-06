package com.example.shared_notes_groovy

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.net.Uri
import android.widget.RemoteViews
import org.json.JSONObject
import java.net.URL
import kotlin.concurrent.thread
import com.example.shared_notes_groovy.R
import es.antonborri.home_widget.HomeWidgetPlugin
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import java.util.concurrent.TimeUnit

class NoteWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        // Schedule periodic background sync (runs even if app not open)
        val work = PeriodicWorkRequestBuilder<WidgetSyncWorker>(15, TimeUnit.MINUTES).build()
        WorkManager.getInstance(context).enqueueUniquePeriodicWork(
            "widget_sync_worker",
            ExistingPeriodicWorkPolicy.KEEP,
            work
        )
        for (appWidgetId in appWidgetIds) {
            // Fetch latest shared widget content from Firebase Realtime Database (REST)
            // so the widget can update even when the app is not running.
            thread {
                var displayText: String? = null
                var imagePath: String? = null
                try {
                    val url = URL("https://shared-notes-app-2a464-default-rtdb.firebaseio.com/notes/widget.json")
                    val jsonText = url.readText()
                    val obj = JSONObject(jsonText)
                    displayText = obj.optString("display_text", null)
                    imagePath = obj.optString("image_path", null)
                } catch (_: Exception) {
                    // Network failed: fall back to locally stored widget data
                }

                val widgetData = HomeWidgetPlugin.getData(context)
                val views = RemoteViews(context.packageName, R.layout.note_widget_layout).apply {
                    val noteText = displayText ?: widgetData.getString("note_text", "No note content yet...")
                    setTextViewText(R.id.note_text, noteText)

                    val imgPath = imagePath ?: widgetData.getString("note_image", "")
                    if (!imgPath.isNullOrEmpty()) {
                        try {
                            val uri = if (imgPath.startsWith("file://")) Uri.parse(imgPath) else Uri.parse("file://$imgPath")
                            setImageViewUri(R.id.note_image, uri)
                            setViewVisibility(R.id.note_image, android.view.View.VISIBLE)
                        } catch (_: Exception) {
                            setViewVisibility(R.id.note_image, android.view.View.GONE)
                        }
                    } else {
                        setViewVisibility(R.id.note_image, android.view.View.GONE)
                    }
                }
                appWidgetManager.updateAppWidget(appWidgetId, views)
            }
        }
    }
}
