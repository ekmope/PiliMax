package com.pilinara.ui.mine

import android.graphics.Bitmap
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.unit.dp
import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.qrcode.QRCodeWriter
import com.pilinara.AppContainer
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext

/** 扫码登录：生成二维码并轮询状态；成功/过期自动回调。 */
@Composable
fun LoginDialog(
    container: AppContainer,
    onDismiss: () -> Unit,
    onLoggedIn: () -> Unit,
) {
    var bitmap by remember { mutableStateOf<Bitmap?>(null) }
    var status by remember { mutableStateOf("使用哔哩哔哩客户端扫码登录") }
    var key by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(Unit) {
        runCatching {
            withContext(Dispatchers.IO) { container.api.qrGenerate() }
        }.onSuccess { qr ->
            key = qr.qrcodeKey
            bitmap = withContext(Dispatchers.Default) { encodeQr(qr.url) }
        }.onFailure {
            status = "二维码生成失败：${it.message}"
        }
    }

    LaunchedEffect(key) {
        val k = key ?: return@LaunchedEffect
        while (true) {
            delay(1500)
            val (code, _) = runCatching {
                kotlinx.coroutines.withContext(Dispatchers.IO) { container.api.qrPoll(k) }
            }.getOrNull() ?: continue
            when (code) {
                0 -> {
                    status = "登录成功"
                    onLoggedIn()
                    return@LaunchedEffect
                }
                86090 -> status = "已扫码，请在手机上确认"
                86038 -> {
                    status = "二维码已过期，请重新打开"
                    return@LaunchedEffect
                }
            }
        }
    }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("登录哔哩哔哩") },
        text = {
            Column {
                val bmp = bitmap
                if (bmp != null) {
                    Image(
                        bitmap = bmp.asImageBitmap(),
                        contentDescription = "登录二维码",
                        modifier = Modifier.size(240.dp),
                    )
                }
                Text(status, modifier = Modifier.padding(top = 12.dp))
            }
        },
        confirmButton = { TextButton(onClick = onDismiss) { Text("关闭") } },
    )
}

private fun encodeQr(content: String): Bitmap {
    val size = 512
    val hints = mapOf(EncodeHintType.MARGIN to 1)
    val matrix = QRCodeWriter().encode(content, BarcodeFormat.QR_CODE, size, size, hints)
    val bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
    for (x in 0 until size) {
        for (y in 0 until size) {
            bmp.setPixel(x, y, if (matrix[x, y]) 0xFF000000.toInt() else 0xFFFFFFFF.toInt())
        }
    }
    return bmp
}
