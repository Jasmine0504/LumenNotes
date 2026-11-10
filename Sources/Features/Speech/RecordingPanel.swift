import SwiftUI

@MainActor
struct RecordingPanel: View {
    @Environment(FontTheme.self) private var theme
    @Bindable var recorder: VoiceRecorder
    var onPause: () -> Void
    var onResume: () -> Void
    var onStop: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(recorder.isPaused ? Color.orange : Color.red)
                    .frame(width: 8, height: 8)
                Text(timeString)
                    .font(theme.font(for: .body).monospacedDigit().weight(.semibold))
                if recorder.isPreparing {
                    ProgressView().controlSize(.small)
                    Text("准备设备端模型…")
                        .font(theme.font(for: .caption))
                        .foregroundStyle(.secondary)
                } else {
                    Text(recorder.isPaused ? "已暂停" : "录音中")
                        .font(theme.font(for: .caption))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(recorder.usesAnalyzer ? "SpeechAnalyzer · 设备端" : "SFSpeechRecognizer")
                    .font(theme.font(for: .caption))
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .center, spacing: 3) {
                ForEach(Array(recorder.levels.enumerated()), id: \.offset) { _, level in
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [LumenTheme.accent, LumenTheme.accentSecondary],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .frame(width: 3, height: max(4, level * 34))
                }
                Spacer(minLength: 6)
                Text("\(wordCount) 字")
                    .font(theme.font(for: .caption).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(height: 38)

            GlassGroup(spacing: 8) {
                HStack(spacing: 8) {
                    GlassIconButton(
                        systemName: recorder.isPaused ? "play.fill" : "pause.fill",
                        label: recorder.isPaused ? "继续录音" : "暂停录音",
                        tint: .primary
                    ) {
                        recorder.isPaused ? onResume() : onPause()
                    }
                    GlassIconButton(systemName: "stop.fill", label: "停止并插入正文", tint: .red) {
                        onStop()
                    }
                    Spacer()
                    GlassIconButton(systemName: "xmark", label: "取消录音") {
                        onCancel()
                    }
                }
            }
        }
        .padding(14)
        .glassPanel(cornerRadius: 24)
    }

    private var timeString: String {
        let value = Int(recorder.elapsed)
        return String(format: "%02d:%02d", value / 60, value % 60)
    }

    private var wordCount: Int {
        recorder.displayText.count
    }
}
