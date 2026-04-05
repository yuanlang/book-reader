import SwiftUI

struct TTSControlPanel: View {
    let viewModel: ReaderViewModel

    @State private var showSpeedPicker = false

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
        .popover(isPresented: $showSpeedPicker) {
            speedPicker
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
                        if abs(viewModel.speed - s) < 0.01 {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }
        .padding()
        .presentationDetents([.medium])
    }
}
