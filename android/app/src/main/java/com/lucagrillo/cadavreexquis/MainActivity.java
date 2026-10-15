package com.lucagrillo.cadavreexquis;

import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.os.Build;
import android.os.Bundle;

import io.flutter.embedding.android.FlutterActivity;

public class MainActivity extends FlutterActivity {
    /** Must match ANDROID_CHANNEL_ID in functions/src/notifications.ts. */
    private static final String STORY_UPDATES_CHANNEL_ID = "story_updates";

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        createNotificationChannel();
    }

    /**
     * The channel the story notifications are posted to, so they show as
     * "Story updates" in the system settings instead of FCM's generic
     * fallback channel. Creating an existing channel again only updates its
     * name (e.g. after a language change).
     */
    private void createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return;
        NotificationChannel channel = new NotificationChannel(
                STORY_UPDATES_CHANNEL_ID,
                getString(R.string.story_updates_channel_name),
                NotificationManager.IMPORTANCE_DEFAULT);
        channel.setDescription(getString(R.string.story_updates_channel_description));
        NotificationManager manager = getSystemService(NotificationManager.class);
        if (manager != null) manager.createNotificationChannel(channel);
    }
}
