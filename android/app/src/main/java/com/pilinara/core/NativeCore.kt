package com.pilinara.core

/**
 * Rust 核心（libpilinara_core.so）的 JNI 桥。
 *
 * 与 [core/src/jni.rs] 中 `Java_com_pilinara_core_NativeCore_*` 导出的函数一一对应：
 * - 核心只接收/返回 JSON 字符串；
 * - 网络与持久化由上层（Kotlin）完成，再通过这里调用纯计算/解析逻辑。
 */
class NativeCore private constructor() {
    companion object {
        init {
            System.loadLibrary("pilinara_core")
        }

        /** 生成「今日推荐单」。 */
        @JvmStatic
        external fun buildTodayWatchPlan(
            historyJson: String,
            candidatesJson: String,
            mode: String,
            strategy: String,
        ): String

        /** 解析源订阅清单 body → manifest JSON。 */
        @JvmStatic
        external fun parseManifest(body: String): String

        /** 应用订阅清单 diff，返回更新后的 instances JSON 数组。 */
        @JvmStatic
        external fun applyManifest(
            subscriptionId: String,
            body: String,
            instancesJson: String,
        ): String

        /** 构造搜索 URL。 */
        @JvmStatic
        external fun buildSearchUrl(instanceJson: String, keyword: String): String

        /** 解析搜索结果页 → subjects JSON。 */
        @JvmStatic
        external fun parseSubjectList(
            instanceJson: String,
            html: String,
            searchUrl: String,
        ): String

        /** 解析条目详情页 → channels JSON。 */
        @JvmStatic
        external fun parseChannels(
            instanceJson: String,
            html: String,
            subjectUrl: String,
        ): String

        /** 从页面 HTML 提取视频直链（返回 JSON 字符串或 null）。 */
        @JvmStatic
        external fun matchVideo(instanceJson: String, html: String): String

        /** 视频直链追加请求头 → JSON object。 */
        @JvmStatic
        external fun videoHeaders(instanceJson: String): String

        /**
         * 应用「大会员无限试用」改写：对 B 站 API 返回 JSON 的会员字段做本地改写。
         *
         * @param body 原始 JSON 字符串
         * @param configJson [VipTrialConfig] 的 JSON，解析失败时回退默认配置
         * @param nowMs 当前时间（Unix 毫秒），用于滚动顺延到期时间
         */
        @JvmStatic
        external fun applyVipTrial(body: String, configJson: String, nowMs: Long): String

        /**
         * 解析旧版 XML 弹幕并合并。
         * @param windowMs 合并时间窗（毫秒），<= 0 表示只排序不合并
         * @return 弹幕 JSON 数组 `[{t,mode,color,text,count}]`
         */
        @JvmStatic
        external fun parseDanmakuXml(body: String, windowMs: Long): String

        /**
         * 解析 seg.so protobuf 弹幕。
         * @param base64Body 原始二进制响应经 Base64 编码后的字符串
         */
        @JvmStatic
        external fun parseDanmakuSegSo(base64Body: String, windowMs: Long): String

        /** 信息流规则过滤：视频数组 JSON + 规则 JSON → 过滤后的数组 JSON。 */
        @JvmStatic
        external fun applyFeedFilter(videosJson: String, rulesJson: String): String

        /**
         * 嗅探视频直链。
         * @param configJson SnifferConfig JSON；空串或 "null" 使用内置规则
         * @return 命中的 URL；未命中返回 "null"
         */
        @JvmStatic
        external fun sniffVideo(html: String, configJson: String): String

        /** 嗅探嵌套页地址（iframe / JS 跳转）。 */
        @JvmStatic
        external fun sniffNested(html: String, configJson: String): String
    }
}