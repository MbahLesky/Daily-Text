package com.lespadev.jwdailytextwidget

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri

/**
 * Resolves the click target for the daily text widget: prefer opening JW
 * Library directly via its jwpub:// deep link scheme, falling back to a
 * browser-openable wol.jw.org URL when JW Library isn't installed.
 *
 * Both URIs are read verbatim from shared storage (already built in Dart
 * from the cached article date — see DailyText.jwpubUri/webUri) rather
 * than reconstructed here, so there's a single source of truth for the URL
 * format.
 */
object WidgetTapHandler {
    /**
     * Builds the [PendingIntent] the widget's root view launches on tap, or
     * `null` if neither URI is available yet (e.g. before the first
     * successful fetch has populated shared storage).
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
            PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun resolveIntent(
        context: Context,
        jwpubUri: String?,
        webUri: String?,
    ): Intent? {
        if (jwpubUri != null) {
            val jwpubIntent = Intent(Intent.ACTION_VIEW, Uri.parse(jwpubUri))
            val resolved = context.packageManager.queryIntentActivities(jwpubIntent, 0)
            if (resolved.isNotEmpty()) return jwpubIntent
        }
        if (webUri != null) {
            return Intent(Intent.ACTION_VIEW, Uri.parse(webUri))
        }
        return null
    }
}
