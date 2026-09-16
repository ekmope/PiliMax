package com.pilinara.vip

import com.pilinara.core.NativeCore

/**
 * 大会员无限试用配置。
 *
 * 与 Rust 核心 [bili_vip::VipTrialConfig] 的 serde 字段名一致：
 * `enabled` / `vipType` / `extendDays`。
 */
data class VipTrialConfig(
    /** 是否启用改写。 */
    val enabled: Boolean = true,
    /** 写入的会员类型：1=月度大会员, 2=年度大会员。 */
    val vipType: Long = 2,
    /** 每次改写时把到期时间顺延的「额外天数」。 */
    val extendDays: Long = 3650,
) {
    fun toJson(): String =
        """{"enabled":$enabled,"vipType":$vipType,"extendDays":$extendDays}"""

    companion object {
        /** 默认配置，序列化为 JSON 供 JNI 传递。 */
        fun defaultJson(): String = VipTrialConfig().toJson()
    }
}

/**
 * 大会员无限试用服务：拦截 B 站 API 返回 JSON，本地改写会员字段。
 *
 * 参考哔哩漫游（BiliRoaming）思路——在本地对 `vipStatus` / `vipType` /
 * `vipDueDate` / `vipLabel` 等字段做改写，把账号视为处于「大会员试用」状态，
 * 并滚动顺延到期时间，达到“无限试用”。纯字符串处理由 Rust 核心完成，本类负责拼参数。
 */
object VipTrialService {

    /** 对 [body] 应用大会员改写，返回改写后的 JSON 字符串。 */
    @JvmStatic
    fun apply(body: String, config: VipTrialConfig = VipTrialConfig()): String =
        NativeCore.applyVipTrial(body, config.toJson(), System.currentTimeMillis())

    /** 仅返回「是否应启用改写」的默认配置 JSON，供上层存储/展示。 */
    @JvmStatic
    fun defaultConfigJson(): String = VipTrialConfig().toJson()
}