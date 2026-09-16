package com.pilinara

import android.app.Activity
import android.graphics.Color
import android.os.Bundle
import android.widget.ScrollView
import android.widget.TextView
import com.pilinara.core.NativeCore

/**
 * 最小壳：验证 JNI 桥与 Rust 核心在 arm64-v8a 设备上可正常加载与调用。
 *
 * 网络接入（B 站首页/历史抓取、animeko 源订阅抓取）是「逐步迁移」的后续工作；
 * 此处以样例数据演示「今日推荐单」与「源订阅/选择器」两套核心解析能力。
 */
class MainActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val text = TextView(this).apply {
            setTextColor(Color.parseColor("#1A1A1A"))
            textSize = 13f
            setPadding(48, 48, 48, 48)
            text = buildDemoReport()
        }

        setContentView(
            ScrollView(this).apply {
                setBackgroundColor(Color.WHITE)
                addView(text)
            },
        )
    }

    private fun buildDemoReport(): String = buildString {
        appendLine("PiliNara 核心自检 (arm64-v8a)")
        appendLine(repeat("-", 40))
        appendLine()

        runCatching { demoTodayWatch() }
            .onSuccess { appendLine(it) }
            .onFailure { appendLine("今日推荐单: 失败 -> ${it.message}") }
        appendLine()

        runCatching { demoSourceSubscription() }
            .onSuccess { appendLine(it) }
            .onFailure { appendLine("源订阅: 失败 -> ${it.message}") }
        appendLine()

        runCatching { demoSelector() }
            .onSuccess { appendLine(it) }
            .onFailure { appendLine("选择器: 失败 -> ${it.message}") }
        appendLine()
        appendLine("全部自检完成。")
    }

    private fun demoTodayWatch(): String {
        val history = """
            [
              {"bvid":"BV1x1","title":"开心每一天 vlog","author_mid":10,"author_name":"UP甲","view_at":1700000000,"progress":-1,"duration":300},
              {"bvid":"BV1x2","title":"Rust 编程入门教程","author_mid":11,"author_name":"UP乙","view_at":1690000000,"progress":-1,"duration":600}
            ]
        """.trimIndent()
        val candidates = """
            [
              {"bvid":"BV1c1","title":"一首好听的翻唱","duration":180,"pubdate":1700000000,"goto":"av","owner_mid":11,"stat_view":10000,"stat_like":500,"stat_danmu":100},
              {"bvid":"BV1c2","title":"Python 实战教程","duration":900,"pubdate":1699000000,"goto":"av","owner_mid":12,"stat_view":8000,"stat_like":800,"stat_danmu":60},
              {"bvid":"BV1c3","title":"旅行 vlog","duration":240,"pubdate":1700000000,"goto":"av","owner_mid":13,"stat_view":12000,"stat_like":300,"stat_danmu":30}
            ]
        """.trimIndent()
        val out = NativeCore.buildTodayWatchPlan(history, candidates, "relax", "balanced")
        return "今日推荐单(relax/balanced) -> $out"
    }

    private fun demoSourceSubscription(): String {
        val manifest = """
            {"mediaSources":[
              {"factoryId":"web-selector","version":1,"arguments":{"name":"新番源A"}},
              {"factoryId":"web-selector","version":1,"arguments":{"name":"电影源B"}}
            ]}
        """.trimIndent()
        val parsed = NativeCore.parseManifest(manifest)
        val applied = NativeCore.applyManifest("sub-1", manifest, "[]")
        return buildString {
            appendLine("源订阅 parseManifest -> $parsed")
            appendLine("源订阅 applyManifest -> $applied")
        }
    }

    private fun demoSelector(): String {
        val instance = """
            {"instanceId":"inst","factoryId":"web-selector","isEnabled":true,"sortOrder":0,
             "arguments":{
                "name":"演示源","tier":1,
                "searchUrl":"https://example.com/s?q={keyword}","searchRemoveSpecial":true,
                "rawBaseUrl":"https://example.com",
                "selectorSubjectFormatFlattened":{"selectItems":"a.item"},
                "selectorChannelFormatNoChannel":{"selectEpisodes":"a"},
                "matchVideo":{"matchVideoUrl":"https://cdn\\.example\\.com/[^\"']+\\.mp4"}
             }}
        """.trimIndent()
        val searchUrl = NativeCore.buildSearchUrl(instance, " 一拳 超人!! ")
        val html = """<a class="item" href="/v/1">番剧 A</a>"""
        val subjects = NativeCore.parseSubjectList(instance, html, searchUrl)
        val detail = """<a href="/p/2">第2集</a><a href="/p/10">第10集</a><a href="/p/1">第1集</a>"""
        val channels = NativeCore.parseChannels(instance, detail, "https://example.com/ani/1")
        val video = NativeCore.matchVideo(instance, """<video src="https://cdn.example.com/v.mp4"></video>""")
        return buildString {
            appendLine("搜索URL -> $searchUrl")
            appendLine("搜索结果 -> $subjects")
            appendLine("线路集数 -> $channels")
            appendLine("视频直链 -> $video")
        }
    }

    private fun StringBuilder.appendLine(line: String = "") {
        append(line)
        append('\n')
    }

    private fun repeat(s: String, n: Int) = s.repeat(n)
}