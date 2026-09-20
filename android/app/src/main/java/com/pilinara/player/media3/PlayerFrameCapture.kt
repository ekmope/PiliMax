package com.pilinara.player.media3

import android.content.ContentValues
import android.graphics.Bitmap
import android.graphics.Matrix
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.view.PixelCopy
import android.view.SurfaceView
import androidx.annotation.RequiresApi
import kotlin.math.roundToInt

/**
 * 当前帧截图（PixelCopy）。
 *
 * 移植自 pili++（loneshu7/PiliPlusPlus，GPL-3.0）
 * `ExoPlayerPlugin.captureFrame / requestPixelCopy / transformCapturedFrame`。
 *
 * 与上游的差别：上游从 Flutter Texture 的 SurfaceProducer 取 surface，这里从
 * PlayerView 里的 SurfaceView 取；失败时不回落到 MediaMetadataRetriever
 * （抓网络流既慢又不准），直接报错给用户。
 *
 * PixelCopy 只保证拿到「GPU 当前呈现的帧」，不含弹幕/控制层——这正是截图要的效果。
 */
internal object PlayerFrameCapture {

    private const val MAX_ATTEMPTS = 3
    private const val RETRY_DELAY_MS = 80L

    fun isSupported(): Boolean = Build.VERSION.SDK_INT >= Build.VERSION_CODES.N

    @RequiresApi(Build.VERSION_CODES.N)
    fun capture(
        surfaceView: SurfaceView?,
        rotationDegrees: Int,
        onResult: (Result<Bitmap>) -> Unit,
    ) {
        val surface = surfaceView?.holder?.surface
        val w = surfaceView?.width ?: 0
        val h = surfaceView?.height ?: 0
        if (surface == null || !surface.isValid || w <= 0 || h <= 0) {
            onResult(Result.failure(IllegalStateException("视频画面不可用")))
            return
        }
        requestCopy(surface, w, h, rotationDegrees, attempt = 0, onResult)
    }

    @RequiresApi(Build.VERSION_CODES.N)
    private fun requestCopy(
        surface: android.view.Surface,
        width: Int,
        height: Int,
        rotationDegrees: Int,
        attempt: Int,
        onResult: (Result<Bitmap>) -> Unit,
    ) {
        val bitmap = runCatching {
            Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        }.getOrElse {
            onResult(Result.failure(it))
            return
        }
        PixelCopy.request(
            surface,
            bitmap,
            { result ->
                if (result != PixelCopy.SUCCESS) {
                    bitmap.recycle()
                    if (result == PixelCopy.ERROR_SOURCE_NO_DATA && attempt < MAX_ATTEMPTS - 1) {
                        Handler(Looper.getMainLooper()).postDelayed({
                            requestCopy(surface, width, height, rotationDegrees, attempt + 1, onResult)
                        }, RETRY_DELAY_MS)
                        return@request
                    }
                    onResult(Result.failure(IllegalStateException("截图失败（code=$result）")))
                    return@request
                }
                onResult(Result.success(rotate(bitmap, rotationDegrees)))
            },
            Handler(Looper.getMainLooper()),
        )
    }

    /** 部分片源带旋转元数据（unappliedRotationDegrees），截图要转正才和看到的一致。 */
    private fun rotate(source: Bitmap, rotationDegrees: Int): Bitmap {
        val normalized = ((rotationDegrees % 360) + 360) % 360
        if (normalized == 0) return source
        val matrix = Matrix().apply {
            preRotate(normalized.toFloat())
        }
        val rotated = Bitmap.createBitmap(source, 0, 0, source.width, source.height, matrix, true)
        if (rotated !== source) source.recycle()
        return rotated
    }

    /** 存到相册 Pictures/PiliNara（Android 10+ 用 MediaStore，免存储权限）。 */
    fun saveToGallery(context: android.content.Context, bitmap: Bitmap, title: String): Result<android.net.Uri> =
        runCatching {
            val values = ContentValues().apply {
                put(MediaStore.Images.Media.DISPLAY_NAME, "$title.jpg")
                put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/PiliNara")
                    put(MediaStore.Images.Media.IS_PENDING, 1)
                }
            }
            val resolver = context.contentResolver
            val uri = requireNotNull(
                resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values),
            ) { "无法创建图片文件" }
            resolver.openOutputStream(uri).use { out ->
                requireNotNull(out) { "无法写入图片文件" }
                require(bitmap.compress(Bitmap.CompressFormat.JPEG, 92, out)) { "图片编码失败" }
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                values.clear()
                values.put(MediaStore.Images.Media.IS_PENDING, 0)
                resolver.update(uri, values, null, null)
            }
            uri
        }
}
