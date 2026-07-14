package com.PiliMax.android

import android.content.Intent
import android.content.res.Configuration
import android.os.Build
import android.os.Bundle
import android.view.Display
import android.view.WindowManager.LayoutParams
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    private lateinit var methodChannel: MethodChannel

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "PiliMax")
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getDisplayRefreshRates" -> result.success(getDisplayRefreshRates())
                else -> result.notImplemented()
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun getCurrentDisplay(): Display? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            display
        } else {
            windowManager.defaultDisplay
        }

    private fun getDisplayRefreshRates(): Map<String, Any?> {
        val currentDisplay = getCurrentDisplay()
        val appRefreshRate = currentDisplay?.refreshRate?.toDouble()
        val modeRefreshRate =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                currentDisplay?.mode?.refreshRate?.toDouble()
            } else {
                appRefreshRate
            }
        val preferredDisplayModeId =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                window.attributes.preferredDisplayModeId
            } else {
                0
            }
        return mapOf(
            "appRefreshRate" to appRefreshRate,
            "modeRefreshRate" to modeRefreshRate,
            "preferredDisplayModeId" to preferredDisplayModeId,
        )
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        if (AndroidHelper.isFoldable) {
            AndroidHelper.ToDart.onConfigurationChanged?.run()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            window.attributes.layoutInDisplayCutoutMode =
                LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
        }
    }

    override fun onDestroy() {
        stopService(Intent(this, com.ryanheise.audioservice.AudioService::class.java))
        super.onDestroy()
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        AndroidHelper.ToDart.onUserLeaveHint?.run()
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration?
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        AndroidHelper.isPipMode = isInPictureInPictureMode
        methodChannel.invokeMethod("onPipChanged", isInPictureInPictureMode)
    }
}
