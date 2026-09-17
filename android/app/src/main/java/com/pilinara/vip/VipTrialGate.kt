package com.pilinara.vip

/**
 * 大会员改写的运行期开关。设置页写入、OkHttp 拦截器读取（@Volatile 保证可见性）。
 */
object VipTrialGate {
    @Volatile
    var config: VipTrialConfig = VipTrialConfig()

    val enabled: Boolean get() = config.enabled

    fun configJson(): String = config.toJson()
}
