import SwiftUI

struct TTSControlPanel: View {
    let viewModel: ReaderViewModel

    @State private var showSpeedPicker = false
    @State private var showVoicePicker = false

    var body: some View {
        VStack(spacing: 8) {
            // Current utterance preview
            if !viewModel.currentUtteranceText.isEmpty {
                Text(viewModel.currentUtteranceText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.horizontal, 16)
            }

            // Playback controls
            HStack(spacing: 24) {
                Button {
                    viewModel.skipPrevious()
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.title2)
                }

                Button {
                    viewModel.togglePlayback()
                } label: {
                    Image(systemName: viewModel.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 44))
                }

                Button {
                    viewModel.skipNext()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.title2)
                }

                Spacer()

                // Voice selector
                Button {
                    showVoicePicker.toggle()
                } label: {
                    Image(systemName: "person.wave.2")
                        .font(.subheadline)
                        .padding(8)
                        .background(.ultraThinMaterial, in: Capsule())
                }

                // Speed selector
                Button {
                    showSpeedPicker.toggle()
                } label: {
                    Text(String(format: "%.1fx", viewModel.speed))
                        .font(.subheadline.monospacedDigit())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: Capsule())
                }
            }
            .padding(.horizontal, 24)
        }
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
        .sheet(isPresented: $showSpeedPicker) {
            speedPicker
        }
        .sheet(isPresented: $showVoicePicker) {
            voicePicker
        }
    }

    private var speedPicker: some View {
        VStack(spacing: 12) {
            Text("朗读速度")
                .font(.headline)

            let speeds: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
            ForEach(speeds, id: \.self) { s in
                Button {
                    viewModel.setSpeed(s)
                    showSpeedPicker = false
                } label: {
                    HStack {
                        Text(String(format: "%.2gx", s))
                        Spacer()
                        if abs(viewModel.speed - s) < 0.01 {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }
        }
        .padding()
        .presentationDetents([.medium])
    }

    private var voicePicker: some View {
        NavigationStack {
            let voices = viewModel.voiceOptions

            List {
                // Default option
                Section {
                    Button {
                        viewModel.setVoice("default")
                        showVoicePicker = false
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text("默认语音")
                                    .foregroundStyle(.primary)
                                Text("根据文本语言自动选择")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if viewModel.selectedVoiceId == nil || viewModel.selectedVoiceId == "default" {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }

                // Chinese voices
                Section("中文语音") {
                    ForEach(voices.chinese) { voice in
                        Button {
                            viewModel.setVoice(voice.id)
                            showVoicePicker = false
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    HStack(spacing: 4) {
                                        Text(voice.name)
                                            .foregroundStyle(.primary)
                                        if voice.isPremium {
                                            Text("高质量")
                                                .font(.caption2)
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1)
                                                .background(.blue.opacity(0.15), in: Capsule())
                                                .foregroundStyle(.blue)
                                        }
                                    }
                                    Text(voice.language)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if viewModel.selectedVoiceId == voice.id {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                }

                // English voices (only standard/enhanced, skip novelty voices)
                Section("English") {
                    let novelty = ["Bad News", "Bahh", "Bells", "Boing", "Bubbles",
                                   "Cellos", "Good News", "Jester", "Junior", "Organ",
                                   "Superstar", "Trinoids", "Whisper", "Zarvox", "Wobble",
                                   "Albert", "Fred", "Kathy", "Ralph"]
                    ForEach(voices.english.filter { !novelty.contains($0.name) }) { voice in
                        Button {
                            viewModel.setVoice(voice.id)
                            showVoicePicker = false
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    HStack(spacing: 4) {
                                        Text(voice.name)
                                            .foregroundStyle(.primary)
                                        if voice.isPremium {
                                            Text("高质量")
                                                .font(.caption2)
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1)
                                                .background(.blue.opacity(0.15), in: Capsule())
                                                .foregroundStyle(.blue)
                                        }
                                    }
                                    Text(voice.language)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if viewModel.selectedVoiceId == voice.id {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("选择语音")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        showVoicePicker = false
                    }
                }
            }
        }
        .presentationDetents([.large])
    }
}
