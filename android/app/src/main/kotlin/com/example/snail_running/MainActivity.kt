package com.example.snail_running

import android.content.Context
import android.media.AudioManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // 메트로놈이 "지금 통화 중인지" 물어보는 통로 — 평소엔 미디어 채널(음악과 함께 재생),
        // 통화 중에만 알람 채널로 바꾸기 위함. 일반 전화와 카카오톡 등 인터넷 통화 모두 포함.
        // 오디오 모드 조회는 별도 권한이 필요 없음
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "snail_running/audio")
            .setMethodCallHandler { call, result ->
                if (call.method == "isInCall") {
                    val mode = (getSystemService(Context.AUDIO_SERVICE) as AudioManager).mode
                    result.success(
                        mode == AudioManager.MODE_IN_CALL || mode == AudioManager.MODE_IN_COMMUNICATION
                    )
                } else {
                    result.notImplemented()
                }
            }
    }
}
