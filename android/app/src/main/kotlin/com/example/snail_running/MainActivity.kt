package com.example.snail_running

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.media.AudioManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // 기록 내보내기·가져오기: 안드로이드 기본 "파일 저장 창 / 파일 선택 창"을 띄우고
    // 사용자가 고른 뒤 돌아올 때까지 Flutter 쪽 응답을 잡아 둠
    private var pendingFileResult: MethodChannel.Result? = null
    private var pendingSaveBytes: ByteArray? = null

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

        // 저장 위치·읽을 파일을 사용자가 직접 고르는 방식이라 저장소 권한이 필요 없음
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "snail_running/files")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveFile" -> {
                        val name = call.argument<String>("fileName")
                        val bytes = call.argument<ByteArray>("bytes")
                        if (name == null || bytes == null || pendingFileResult != null) {
                            result.error("busy_or_invalid", "파일 저장을 시작할 수 없습니다.", null)
                        } else {
                            pendingFileResult = result
                            pendingSaveBytes = bytes
                            val intent = Intent(Intent.ACTION_CREATE_DOCUMENT)
                            intent.addCategory(Intent.CATEGORY_OPENABLE)
                            intent.type = "application/json"
                            intent.putExtra(Intent.EXTRA_TITLE, name)
                            startActivityForResult(intent, REQUEST_SAVE_FILE)
                        }
                    }
                    "pickFile" -> {
                        if (pendingFileResult != null) {
                            result.error("busy_or_invalid", "파일 선택을 시작할 수 없습니다.", null)
                        } else {
                            pendingFileResult = result
                            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT)
                            intent.addCategory(Intent.CATEGORY_OPENABLE)
                            intent.type = "*/*"
                            startActivityForResult(intent, REQUEST_PICK_FILE)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_SAVE_FILE && requestCode != REQUEST_PICK_FILE) return
        val result = pendingFileResult ?: return
        val bytes = pendingSaveBytes
        pendingFileResult = null
        pendingSaveBytes = null
        val uri = data?.data
        // 사용자가 취소하면 저장은 false, 선택은 null로 돌려줌
        if (resultCode != Activity.RESULT_OK || uri == null) {
            if (requestCode == REQUEST_SAVE_FILE) result.success(false) else result.success(null)
            return
        }
        try {
            if (requestCode == REQUEST_SAVE_FILE) {
                val out = contentResolver.openOutputStream(uri)
                if (out == null || bytes == null) {
                    result.error("io", "파일을 열 수 없습니다.", null)
                } else {
                    out.use { it.write(bytes) }
                    result.success(true)
                }
            } else {
                val input = contentResolver.openInputStream(uri)
                if (input == null) {
                    result.error("io", "파일을 열 수 없습니다.", null)
                } else {
                    result.success(input.use { it.readBytes() })
                }
            }
        } catch (e: Exception) {
            result.error("io", e.message, null)
        }
    }

    companion object {
        private const val REQUEST_SAVE_FILE = 4101
        private const val REQUEST_PICK_FILE = 4102
    }
}
