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
    private lateinit var routeRestoreMethodChannel: MethodChannel
    private var nativeCrashChannel: NativeCrashChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "PiliMax")
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getDisplayRefreshRates" -> result.success(getDisplayRefreshRates())
                else -> result.notImplemented()
            }
        }

        routeRestoreMethodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            RouteRestoreLifecycle.CHANNEL_NAME,
        )
        routeRestoreMethodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getRestoreDecision" ->
                    result.success(RouteRestoreLifecycle.getRestoreDecision())
                "markTaskRemoved" -> {
                    RouteRestoreLifecycle.markTaskRemoved(this)
                    result.success(null)
                }
                "markIntentionalExit" -> {
                    RouteRestoreLifecycle.markIntentionalExit(this)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        nativeCrashChannel = NativeCrashChannel(
            applicationContext,
            flutterEngine.dartExecutor.binaryMessenger,
        )
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        nativeCrashChannel?.dispose()
        nativeCrashChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
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
        RouteRestoreLifecycle.onActivityCreated(
            this,
            intent,
            isRecreation = savedInstanceState != null,
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            window.attributes.layoutInDisplayCutoutMode =
                LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
        }
    }

    override fun onStart() {
        super.onStart()
        RouteRestoreLifecycle.onActivityStarted(this)
    }

    override fun onStop() {
        RouteRestoreLifecycle.onActivityStopped(this)
        super.onStop()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        RouteRestoreLifecycle.onNewIntent(this, intent)
    }

    override fun onDestroy() {
        RouteRestoreLifecycle.onActivityDestroyed(
            this,
            isFinishing,
            isChangingConfigurations,
        )
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
