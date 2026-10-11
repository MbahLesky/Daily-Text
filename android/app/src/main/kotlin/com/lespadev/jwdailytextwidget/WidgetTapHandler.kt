package com.lespadev.jwdailytextwidget

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri

/**
 * Resolves the click target for the daily text widget:
 * 1. Prefer opening JW Library directly via its jwpub:// deep link scheme.
 * 2. Fall back to a browser-openable wol.jw.org URL when JW Library is not installed.
 * 3. Fall back to launching the Daily Text app itself if neither URL is available.
 */
object WidgetTapHandler {
    /**
     * Builds the [PendingIntent] the widget's root view launches on tap.
     */
    fun buildPendingIntent(
        context: Context,
        jwpubUri: String?,
        webUri: String?,
    ): PendingIntent? {
        val intent = resolveIntent(context, jwpubUri, webUri) ?: return null
        return PendingIntent.getActivity(
            context,
            0,
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }

    private fun resolveIntent(
        context: Context,
        jwpubUri: String?,
        webUri: String?,
    ): Intent? {
        if (!jwpubUri.isNullOrEmpty()) {
            val jwpubIntent = Intent(Intent.ACTION_VIEW, Uri.parse(jwpubUri))
            val resolved = context.packageManager.queryIntentActivities(jwpubIntent, 0)
            if (resolved.isNotEmpty()) {
                return jwpubIntent
            }
        }
        if (!webUri.isNullOrEmpty()) {
            return Intent(Intent.ACTION_VIEW, Uri.parse(webUri))
        }
        // Fallback to opening this app itself
        return context.packageManager.getLaunchIntentForPackage(context.packageName)
    }

    /**
     * Returns true if the JW Library app is installed on this device.
     */
    fun isJwLibraryInstalled(context: Context): Boolean {
        val testIntent = Intent(Intent.ACTION_VIEW, Uri.parse("jwpub://dt/r1/lp-e/2026/1/1"))
        return context.packageManager.queryIntentActivities(testIntent, 0).isNotEmpty()
    }
}
