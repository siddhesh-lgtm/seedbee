package com.example.shared_notes_groovy

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.net.Uri
import android.widget.RemoteViews
import com.example.shared_notes_groovy.R
import es.antonborri.home_widget.HomeWidgetPlugin

class NoteWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            val widgetData = HomeWidgetPlugin.getData(context)
            val views = RemoteViews(context.packageName, R.layout.note_widget_layout).apply {
                val noteText = widgetData.getString("note_text", "No note content yet...")
                setTextViewText(R.id.note_text, noteText)

                val imgPath = widgetData.getString("note_image", "")
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

                val bg = widgetData.getInt("note_bg", 0)
                if (bg != 0) {
                    setInt(R.id.widget_container, "setBackgroundColor", bg)
                }

                val textColor = widgetData.getInt("note_text_color", 0)
                if (textColor != 0) {
                    setTextColor(R.id.note_text, textColor)
                }
            }
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
