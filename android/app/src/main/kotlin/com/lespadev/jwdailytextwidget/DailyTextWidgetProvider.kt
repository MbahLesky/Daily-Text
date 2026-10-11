package com.lespadev.jwdailytextwidget

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin

/** Renders the daily text (scripture + comment) onto the home screen widget. */
class DailyTextWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        val prefs = HomeWidgetPlugin.getData(context)
        val scripture = prefs.getString("scripture", "Loading today's text…")
        val comment = prefs.getString("comment", "")
        val dateTitle = prefs.getString("dateTitle", null) ?: prefs.getString("date", "")
        val jwpubUri = prefs.getString("jwpubUri", null)
        val webUri = prefs.getString("webUri", null)

        val isJwLib = WidgetTapHandler.isJwLibraryInstalled(context)
        val footerText = if (isJwLib) "Tap to open in JW Library" else "Tap to read on WOL"

        val pendingIntent = WidgetTapHandler.buildPendingIntent(context, jwpubUri, webUri)

        for (widgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.daily_text_widget)
            views.setTextViewText(R.id.widget_scripture, scripture)
            views.setTextViewText(R.id.widget_comment, comment)
            if (!dateTitle.isNullOrEmpty()) {
                views.setTextViewText(R.id.widget_date, dateTitle)
            }
            views.setTextViewText(R.id.widget_footer, footerText)

            if (pendingIntent != null) {
                views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
