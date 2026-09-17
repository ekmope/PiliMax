package com.pilinara.api

import java.security.MessageDigest

/**
 * WBI 请求签名（B 站 web 接口风控）。
 *
 * img_key/sub_key 来自 `/x/web-interface/nav.wbi_img`，经过固定置换表取前 32 位
 * 得到 mixin_key，再对「参数串 + mixin_key」做 MD5 得到 w_rid。
 */
object Wbi {

    private val MIXIN_TABLE = intArrayOf(
        46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35,
        27, 43, 5, 49, 33, 9, 42, 19, 29, 28, 14, 39, 12, 38, 41, 13,
        37, 48, 7, 16, 24, 55, 40, 61, 26, 17, 0, 1, 60, 51, 30, 4,
        22, 25, 54, 21, 56, 59, 6, 63, 57, 62, 11, 36, 20, 34, 44, 52,
    )

    fun mixinKey(imgKey: String, subKey: String): String {
        val raw = imgKey + subKey
        return buildString(32) {
            for (i in 0 until 32) append(raw[MIXIN_TABLE[i]])
        }
    }

    /** 返回带 wts / w_rid 的查询串（已 URL 编码，以 & 连接）。 */
    fun sign(params: Map<String, String>, mixinKey: String): String {
        val wts = System.currentTimeMillis() / 1000
        val sorted = (params + ("wts" to wts.toString())).toSortedMap()
        val query = sorted.entries.joinToString("&") { (k, v) ->
            "${enc(k)}=${enc(filterValue(v))}"
        }
        val wRid = md5Hex(query + mixinKey)
        return "$query&w_rid=$wRid"
    }

    private fun filterValue(v: String): String =
        v.filter { it != '!' && it != '\'' && it != '(' && it != ')' && it != '*' }

    private fun enc(s: String): String =
        java.net.URLEncoder.encode(s, "UTF-8")

    private fun md5Hex(s: String): String {
        val digest = MessageDigest.getInstance("MD5").digest(s.toByteArray(Charsets.UTF_8))
        return buildString(32) {
            for (b in digest) {
                val v = b.toInt() and 0xFF
                append(HEX[v ushr 4])
                append(HEX[v and 0x0F])
            }
        }
    }

    private const val HEX = "0123456789abcdef"
}
