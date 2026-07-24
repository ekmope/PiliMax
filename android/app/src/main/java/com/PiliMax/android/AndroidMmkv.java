package com.PiliMax.android;

import android.content.Context;

import androidx.annotation.Keep;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import com.github.dart_lang.jni_flutter.JniFlutterPlugin;
import com.tencent.mmkv.MMKV;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.Iterator;
import java.util.Locale;

@Keep
public final class AndroidMmkv {
    private static final String BOX_PREFIX = "pilimax_";

    private static volatile boolean initialized = false;
    private static volatile boolean unavailable = false;

    private AndroidMmkv() {
    }

    public static boolean initialize() {
        return initialize(JniFlutterPlugin.getApplicationContext());
    }

    public static boolean initialize(Context context) {
        if (initialized) return true;
        if (unavailable || context == null) return false;

        synchronized (AndroidMmkv.class) {
            if (initialized) return true;
            try {
                MMKV.initialize(context.getApplicationContext());
                initialized = true;
                return true;
            } catch (Throwable ignored) {
                unavailable = true;
                return false;
            }
        }
    }

    public static boolean isAvailable() {
        return initialized || initialize();
    }

    @Nullable
    public static String exportBox(@NonNull String name) {
        try {
            MMKV mmkv = box(name);
            if (mmkv == null) return null;

            JSONObject entries = new JSONObject();
            String[] keys = mmkv.allKeys();
            if (keys != null) {
                for (String key : keys) {
                    entries.put(key, mmkv.decodeString(key, ""));
                }
            }
            return entries.toString();
        } catch (Throwable ignored) {
            return null;
        }
    }

    /** Export only keys (no values) for cheap lazy box open. */
    @Nullable
    public static String exportKeys(@NonNull String name) {
        try {
            MMKV mmkv = box(name);
            if (mmkv == null) return null;

            JSONArray keysJson = new JSONArray();
            String[] keys = mmkv.allKeys();
            if (keys != null) {
                for (String key : keys) {
                    keysJson.put(key);
                }
            }
            return keysJson.toString();
        } catch (Throwable ignored) {
            return null;
        }
    }

    public static int count(@NonNull String name) {
        try {
            MMKV mmkv = box(name);
            if (mmkv == null) return -1;
            String[] keys = mmkv.allKeys();
            return keys == null ? 0 : keys.length;
        } catch (Throwable ignored) {
            return -1;
        }
    }

    public static boolean containsKey(@NonNull String name, @NonNull String key) {
        try {
            MMKV mmkv = box(name);
            return mmkv != null && mmkv.containsKey(key);
        } catch (Throwable ignored) {
            return false;
        }
    }

    @Nullable
    public static String getString(@NonNull String name, @NonNull String key) {
        try {
            MMKV mmkv = box(name);
            if (mmkv == null || !mmkv.containsKey(key)) return null;
            return mmkv.decodeString(key, null);
        } catch (Throwable ignored) {
            return null;
        }
    }

    public static boolean replaceBox(@NonNull String name, @NonNull String json) {
        String previous = exportBox(name);
        try {
            MMKV mmkv = box(name);
            if (mmkv == null) return false;

            JSONObject entries = new JSONObject(json);
            if (writeEntries(mmkv, entries)) return true;
            return previous != null && writeEntries(mmkv, new JSONObject(previous)) && false;
        } catch (Throwable ignored) {
            if (previous != null) {
                try {
                    MMKV mmkv = box(name);
                    if (mmkv != null) writeEntries(mmkv, new JSONObject(previous));
                } catch (Throwable restoreIgnored) {
                    // The caller still receives failure; the export remains available for diagnosis.
                }
            }
            return false;
        }
    }

    private static boolean writeEntries(@NonNull MMKV mmkv, @NonNull JSONObject entries) {
        mmkv.clearAll();
        for (Iterator<String> it = entries.keys(); it.hasNext(); ) {
            String key = it.next();
            if (!mmkv.encode(key, entries.optString(key))) return false;
        }
        mmkv.sync();
        return true;
    }

    public static boolean putString(
            @NonNull String name,
            @NonNull String key,
            @NonNull String value
    ) {
        try {
            MMKV mmkv = box(name);
            return mmkv != null && mmkv.encode(key, value);
        } catch (Throwable ignored) {
            return false;
        }
    }

    public static boolean putAllStrings(@NonNull String name, @NonNull String json) {
        String previous = exportBox(name);
        try {
            MMKV mmkv = box(name);
            if (mmkv == null) return false;

            JSONObject entries = new JSONObject(json);
            for (Iterator<String> it = entries.keys(); it.hasNext(); ) {
                String key = it.next();
                if (!mmkv.encode(key, entries.optString(key))) {
                    if (previous != null) {
                        writeEntries(mmkv, new JSONObject(previous));
                    }
                    return false;
                }
            }
            return true;
        } catch (Throwable ignored) {
            if (previous != null) {
                try {
                    MMKV mmkv = box(name);
                    if (mmkv != null) writeEntries(mmkv, new JSONObject(previous));
                } catch (Throwable restoreIgnored) {
                    // Caller receives failure and keeps its Dart cache unchanged.
                }
            }
            return false;
        }
    }

    public static boolean removeValue(@NonNull String name, @NonNull String key) {
        try {
            MMKV mmkv = box(name);
            if (mmkv == null) return false;
            mmkv.removeValueForKey(key);
            return true;
        } catch (Throwable ignored) {
            return false;
        }
    }

    public static boolean removeValues(@NonNull String name, @NonNull String keysJson) {
        try {
            MMKV mmkv = box(name);
            if (mmkv == null) return false;

            JSONArray keys = new JSONArray(keysJson);
            String[] keyArray = new String[keys.length()];
            for (int i = 0; i < keys.length(); i++) {
                keyArray[i] = keys.getString(i);
            }
            mmkv.removeValuesForKeys(keyArray);
            return true;
        } catch (Throwable ignored) {
            return false;
        }
    }

    public static boolean clearBox(@NonNull String name) {
        try {
            MMKV mmkv = box(name);
            if (mmkv == null) return false;
            mmkv.clearAll();
            mmkv.sync();
            return true;
        } catch (Throwable ignored) {
            return false;
        }
    }

    public static boolean sync(@NonNull String name) {
        try {
            MMKV mmkv = box(name);
            if (mmkv == null) return false;
            mmkv.sync();
            return true;
        } catch (Throwable ignored) {
            return false;
        }
    }

    @Nullable
    private static MMKV box(String name) {
        if (!isAvailable()) return null;
        return MMKV.mmkvWithID(
                BOX_PREFIX + name.toLowerCase(Locale.ROOT),
                MMKV.SINGLE_PROCESS_MODE
        );
    }
}
