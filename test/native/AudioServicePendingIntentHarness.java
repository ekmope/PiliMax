package com.ryanheise.audioservice;

import java.util.*;

/** Pure-JVM API doubles around verbatim methods extracted from the patched dependency. */
public class AudioServicePendingIntentHarness {
    private static void check(boolean value, String message) {
        if (!value) throw new AssertionError(message);
    }

    private static MediaControl custom(String name) {
        return new MediaControl("drawable/test", name, 0, new CustomMediaAction(name, null));
    }

    private static PendingIntent customIntent(AudioService service, String name) {
        return service.createAction("drawable/test", name, 0, name).intent;
    }

    private static void update(AudioService service, List<MediaControl> controls, long position, int[] compact) {
        service.setState(controls, 0, compact, AudioProcessingState.ready, true,
                position, position, 1, position, null, null, 0, 0, false, null);
    }

    public static void main(String[] args) {
        AudioService service = new AudioService();
        List<MediaControl> controls = new ArrayList<>(List.of(custom("ACTION_REFRESH"),
                new MediaControl("drawable/test", "Play", 126, null), custom("ACTION_DM")));
        int[] compact = {0, 1, 2};
        for (int i = 0; i < 10000; i++) update(service, controls, i, compact);
        check(PendingIntent.records.size() == 3,
                "position updates allocated " + PendingIntent.records.size() + " PendingIntents instead of 3");
        check(PendingIntent.calls == 3, "unchanged controls still rebuild notification actions");
        check(service.mediaSession.updates == 10000, "position updates did not reach MediaSession");
        check(service.mediaSession.lastPosition == 9999, "latest position was lost");
        PendingIntent refresh = service.nativeActions.get(0).intent;
        PendingIntent danmaku = service.nativeActions.get(2).intent;
        check(refresh != danmaku, "custom actions share a token");
        check("ACTION_REFRESH".equals(refresh.dispatch()), "refresh dispatch changed");
        check("ACTION_DM".equals(danmaku.dispatch()), "danmaku dispatch changed");
        check((refresh.flags & PendingIntent.FLAG_UPDATE_CURRENT) != 0, "missing update-current flag");
        check((refresh.flags & PendingIntent.FLAG_IMMUTABLE) != 0, "missing immutable flag");
        update(service, controls, 10000, new int[]{2, 1, 0});
        check(PendingIntent.calls == 3, "compact-only change rebuilt actions");
        check(Arrays.equals(service.compactActionIndices, new int[]{2, 1, 0}), "compact layout was lost");
        controls.set(1, new MediaControl("drawable/test", "Pause", 127, null));
        update(service, controls, 10001, compact);
        check(service.nativeActions.get(1).label.equals("Pause"), "mutated controls were not rebuilt");
        check(service.nativeActions.get(0).intent == refresh, "refresh identity changed on pause");
        check(service.nativeActions.get(2).intent == danmaku, "danmaku identity changed on pause");
        check(PendingIntent.records.size() == 4, "pause caused custom PendingIntent growth");
        for (int i = 0; i < 10000; i++) update(service, controls, 10002 + i, compact);
        check(PendingIntent.records.size() == 4, "repeated pause-state updates grew tokens");
        check(service.nativeActions.get(0).intent.dispatch().equals("ACTION_REFRESH"), "refresh stopped dispatching");
        check(service.nativeActions.get(2).intent.dispatch().equals("ACTION_DM"), "danmaku stopped dispatching");
        PendingIntent hashA = customIntent(service, "Aa");
        PendingIntent hashB = customIntent(service, "BB");
        check("Aa".hashCode() == "BB".hashCode(), "hash-collision fixture is invalid");
        check(hashA != hashB, "custom-action identities collide by hash");
        check(customIntent(service, "a/b") != customIntent(service, "a%2Fb"),
                "URI encoding aliases different action names");
        AudioService recreated = new AudioService();
        check(customIntent(recreated, "ACTION_REFRESH") == refresh,
                "service recreation changes custom-action identity");
        Build.VERSION.SDK_INT = 22;
        PendingIntent legacy = customIntent(recreated, "legacy");
        check((legacy.flags & PendingIntent.FLAG_IMMUTABLE) == 0, "legacy Android got an unsupported flag");
        check(legacy.dispatch().equals("legacy"), "legacy action dispatch failed");
        System.out.println("PendingIntent regression: 20,000 position updates, changed controls, compact layout, dispatch, collision and recreation checks passed");
    }
}

class AudioService {
    static final String NOTIFICATION_CUSTOM_ACTION = "notification.custom";
    static final String NOTIFICATION_CUSTOM_ACTION_NAME = "notification.custom.name";
    static final long AUTO_ENABLED_ACTIONS = 0;
    List<MediaControl> controls = new ArrayList<>();
    List<NotificationCompat.Action> nativeActions = new ArrayList<>();
    List<PlaybackStateCompat.CustomAction> customActions = new ArrayList<>();
    int[] compactActionIndices;
    boolean playing;
    AudioProcessingState processingState = AudioProcessingState.idle;
    int repeatMode, shuffleMode;
    MediaMetadata mediaMetadata;
    MediaSession mediaSession = new MediaSession();
    String getPackageName() { return "com.PiliMax.android"; }
    int getResourceId(String resource) { return 1; }
    int toKeyCode(long code) { return (int) code; }
    int getPlaybackState() { return 1; }
    PlaybackStateCompat.CustomAction createCustomAction(MediaControl control) {
        return control.customAction == null ? null : new PlaybackStateCompat.CustomAction();
    }
    void enterPlayingState() {}
    void exitPlayingState() {}
    void updateNotification() {}
    void stop() {}

    /* ACTUAL_DEPENDENCY_METHODS */
}

enum AudioProcessingState { idle, ready, buffering }
class Build { static class VERSION { static int SDK_INT = 37; } }
class Uri {
    final String value;
    Uri(String value) { this.value = value; }
    public String toString() { return value; }
    static class Builder {
        String value = "";
        Builder scheme(String scheme) { value = scheme + "://"; return this; }
        Builder authority(String authority) { value += authority; return this; }
        Builder appendPath(String path) {
            value += "/" + java.net.URLEncoder.encode(path, java.nio.charset.StandardCharsets.UTF_8).replace("+", "%20");
            return this;
        }
        Uri build() { return new Uri(value); }
    }
}
class Intent {
    static final String ACTION_MEDIA_BUTTON = "media.button", EXTRA_KEY_EVENT = "key";
    String action;
    Uri data;
    Map<String, Object> extras = new HashMap<>();
    Intent(Object context, Class<?> receiver) {}
    void setAction(String action) { this.action = action; }
    void setData(Uri data) { this.data = data; }
    void putExtra(String key, Object value) { extras.put(key, value); }
}
class PendingIntent {
    static final int FLAG_UPDATE_CURRENT = 1, FLAG_IMMUTABLE = 2;
    static final Map<String, PendingIntent> records = new HashMap<>();
    static int calls;
    Intent intent;
    int flags;
    static PendingIntent getBroadcast(Object context, int code, Intent intent, int flags) {
        calls++;
        String identity = code + "|" + intent.action + "|" + intent.data;
        PendingIntent result = records.computeIfAbsent(identity, key -> new PendingIntent());
        result.intent = intent;
        result.flags = flags;
        return result;
    }
    String dispatch() { return (String) intent.extras.get(AudioService.NOTIFICATION_CUSTOM_ACTION_NAME); }
}
class NotificationCompat {
    static class Action {
        final String label;
        final PendingIntent intent;
        Action(int icon, String label, PendingIntent intent) { this.label = label; this.intent = intent; }
    }
}
class MediaButtonReceiver { static final String ACTION_NOTIFICATION_DELETE = "notification.delete"; }
class KeyEvent {
    static final int KEYCODE_UNKNOWN = 0, ACTION_DOWN = 0;
    KeyEvent(int action, int keyCode) {}
}
class Bundle { void putString(String key, String value) {} }
class MediaConstants { static final String PLAYBACK_STATE_EXTRAS_KEY_MEDIA_ID = "id"; }
class MediaMetadata { Description getDescription() { return new Description(); } }
class Description { String getMediaId() { return "id"; } }
class MediaSession {
    int updates;
    long lastPosition;
    void setPlaybackState(PlaybackStateCompat state) { updates++; lastPosition = state.position; }
    void setRepeatMode(int value) {}
    void setShuffleMode(int value) {}
    void setCaptioningEnabled(boolean value) {}
}
class PlaybackStateCompat {
    static final int ERROR_CODE_UNKNOWN_ERROR = 0;
    long position;
    static class CustomAction {}
    static class Builder {
        PlaybackStateCompat state = new PlaybackStateCompat();
        Builder setActions(long value) { return this; }
        Builder setState(int value, long position, float speed, long time) { state.position = position; return this; }
        Builder setBufferedPosition(long value) { return this; }
        Builder addCustomAction(CustomAction value) { return this; }
        Builder setActiveQueueItemId(long value) { return this; }
        Builder setErrorMessage(int code, String message) { return this; }
        Builder setExtras(Bundle value) { return this; }
        PlaybackStateCompat build() { return state; }
    }
}
