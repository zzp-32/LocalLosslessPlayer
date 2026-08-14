import Foundation
import SwiftUI

struct SoundEffectsCenterView: View {
    @EnvironmentObject private var player: PlayerViewModel
    @EnvironmentObject private var settings: AppSettings

    private let playbackRates = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    dspHeader
                    responseSection
                    equalizerSection
                    toneSection
                    outputSection
                    speedSection
                    currentTrackSection
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(PlayerPalette.background.ignoresSafeArea())
            .navigationTitle("音效中心")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("重置") {
                        settings.resetAudioEffects()
                        applyAudioSettings()
                    }
                    .foregroundStyle(PlayerPalette.green)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { applyAudioSettings() }
    }

    private var dspHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 25, weight: .semibold))
                .foregroundStyle(PlayerPalette.green)
                .frame(width: 48, height: 48)
                .background(PlayerPalette.raised)
                .cornerRadius(8)
            VStack(alignment: .leading, spacing: 3) {
                Text("32 段 Graphic EQ")
                    .font(.headline)
                    .foregroundStyle(PlayerPalette.primary)
                Text("DSP 实时处理")
                    .font(.caption)
                    .foregroundStyle(PlayerPalette.secondary)
            }
            Spacer()
            Circle()
                .fill(PlayerPalette.green)
                .frame(width: 8, height: 8)
                .shadow(color: PlayerPalette.green.opacity(0.65), radius: 5)
        }
        .padding(.top, 8)
    }

    private var responseSection: some View {
        VStack(spacing: 8) {
            HStack {
                Text("实时 EQ 曲线")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PlayerPalette.primary)
                Spacer()
                Text("±12 dB")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(PlayerPalette.secondary)
            }
            EQResponseCurve(gains: settings.equalizerGains)
                .frame(height: 116)
        }
        .padding(14)
        .background(PlayerPalette.surface)
        .cornerRadius(8)
    }

    private var equalizerSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Menu {
                    ForEach(AppSettings.EqualizerPreset.allCases) { preset in
                        Button {
                            settings.applyEqualizerPreset(preset)
                            applyAudioSettings()
                        } label: {
                            if settings.selectedEqualizerPreset == preset {
                                Label(preset.title, systemImage: "checkmark")
                            } else {
                                Text(preset.title)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "dial.medium")
                        Text(settings.selectedEqualizerPreset.title)
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PlayerPalette.primary)
                    .padding(.horizontal, 12)
                    .frame(height: 38)
                    .background(PlayerPalette.raised)
                    .cornerRadius(7)
                }
                Spacer()
                Button("平坦") {
                    settings.applyEqualizerPreset(.standard)
                    applyAudioSettings()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PlayerPalette.green)
                .frame(minWidth: 54, minHeight: 38)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .bottom, spacing: 0) {
                    ForEach(settings.equalizerGains.indices, id: \.self) { index in
                        equalizerBand(at: index)
                    }
                }
                .padding(.horizontal, 2)
            }
            .frame(height: 238)
        }
        .padding(14)
        .background(PlayerPalette.surface)
        .cornerRadius(8)
    }

    private func equalizerBand(at index: Int) -> some View {
        VStack(spacing: 7) {
            Text(String(format: "%+.1f", settings.equalizerGains[index]))
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(settings.equalizerGains[index] == 0 ? PlayerPalette.secondary : PlayerPalette.green)
                .frame(width: 44)

            Slider(
                value: Binding(
                    get: { settings.equalizerGains[index] },
                    set: {
                        settings.setEqualizerGain($0, at: index)
                        applyAudioSettings()
                    }
                ),
                in: -12...12,
                step: 0.5
            )
            .tint(PlayerPalette.green)
            .frame(width: 154)
            .rotationEffect(.degrees(-90))
            .frame(width: 44, height: 154)

            Text(frequencyLabel(AppSettings.equalizerFrequencies[index]))
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(PlayerPalette.secondary)
                .frame(width: 44)
        }
        .frame(width: 44)
    }

    private var toneSection: some View {
        VStack(spacing: 16) {
            sectionTitle("音色", icon: "waveform.path")
            effectSlider(
                "低音增强",
                value: Binding(get: { settings.bassBoost }, set: { settings.bassBoost = $0; applyAudioSettings() }),
                range: 0...12,
                suffix: " dB"
            )
            effectSlider(
                "高音增强",
                value: Binding(get: { settings.trebleBoost }, set: { settings.trebleBoost = $0; applyAudioSettings() }),
                range: 0...12,
                suffix: " dB"
            )
            effectSlider(
                "立体声扩展",
                value: Binding(get: { settings.stereoExpansion }, set: { settings.stereoExpansion = $0; applyAudioSettings() }),
                range: 0...100,
                suffix: "%"
            )
            Toggle(isOn: Binding(get: { settings.loudness }, set: { settings.loudness = $0; applyAudioSettings() })) {
                Label("响度增强", systemImage: "speaker.wave.3.fill")
                    .foregroundStyle(PlayerPalette.primary)
            }
            .tint(PlayerPalette.green)
        }
        .padding(14)
        .background(PlayerPalette.surface)
        .cornerRadius(8)
    }

    private var outputSection: some View {
        VStack(spacing: 16) {
            sectionTitle("输出", icon: "hifispeaker.2.fill")
            effectSlider(
                "前置增益",
                value: Binding(get: { settings.preamp }, set: { settings.preamp = $0; applyAudioSettings() }),
                range: -12...12,
                suffix: " dB"
            )
            effectSlider(
                "左右声道平衡",
                value: Binding(get: { settings.balance }, set: { settings.balance = $0; applyAudioSettings() }),
                range: -100...100,
                suffix: ""
            )
            Toggle(isOn: Binding(get: { settings.monoAudio }, set: { settings.monoAudio = $0; applyAudioSettings() })) {
                Label("单声道", systemImage: "speaker.fill")
                    .foregroundStyle(PlayerPalette.primary)
            }
            .tint(PlayerPalette.green)
        }
        .padding(14)
        .background(PlayerPalette.surface)
        .cornerRadius(8)
    }

    private var speedSection: some View {
        HStack {
            sectionTitle("播放速度", icon: "gauge.with.dots.needle.bottom.50percent")
            Spacer()
            Picker("播放速度", selection: Binding(
                get: { settings.playbackRate },
                set: { settings.playbackRate = $0; applyAudioSettings() }
            )) {
                ForEach(playbackRates, id: \.self) { rate in
                    Text(speedLabel(rate)).tag(rate)
                }
            }
            .pickerStyle(.menu)
            .tint(PlayerPalette.green)
        }
        .padding(14)
        .background(PlayerPalette.surface)
        .cornerRadius(8)
    }

    @ViewBuilder
    private var currentTrackSection: some View {
        if let song = player.currentSong {
            HStack(spacing: 12) {
                ArtworkTile(title: song.title, size: 48, artworkPath: song.artworkPath)
                VStack(alignment: .leading, spacing: 4) {
                    Text(song.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PlayerPalette.primary)
                        .lineLimit(1)
                    Text(song.artist.nilIfEmpty ?? "未知艺术家")
                        .font(.caption)
                        .foregroundStyle(PlayerPalette.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button { player.toggle() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.headline)
                        .foregroundStyle(PlayerPalette.background)
                        .frame(width: 42, height: 42)
                        .background(PlayerPalette.green)
                        .clipShape(Circle())
                }
                .accessibilityLabel(player.isPlaying ? "暂停" : "播放")
            }
            .padding(12)
            .background(PlayerPalette.surface)
            .cornerRadius(8)
        }
    }

    private func sectionTitle(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(PlayerPalette.primary)
    }

    private func effectSlider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        suffix: String
    ) -> some View {
        VStack(spacing: 7) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(PlayerPalette.primary)
                Spacer()
                Text(String(format: "%.1f%@", value.wrappedValue, suffix))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(PlayerPalette.secondary)
            }
            Slider(value: value, in: range, step: 0.5)
                .tint(PlayerPalette.green)
        }
    }

    private func frequencyLabel(_ frequency: Double) -> String {
        if frequency >= 1_000 {
            let value = frequency / 1_000
            return value.rounded() == value ? String(format: "%.0fK", value) : String(format: "%.1fK", value)
        }
        return frequency.rounded() == frequency ? String(format: "%.0f", frequency) : String(format: "%.1f", frequency)
    }

    private func speedLabel(_ value: Double) -> String {
        value == 1 ? "1×" : String(format: "%g×", value)
    }

    private func applyAudioSettings() {
        player.apply(settings: settings)
    }
}

private struct EQResponseCurve: View {
    let gains: [Double]

    var body: some View {
        Canvas { context, size in
            let middleY = size.height / 2
            let gridColor = Color.white.opacity(0.09)

            for row in 0...4 {
                let y = size.height * CGFloat(row) / 4
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y))
                line.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(line, with: .color(gridColor), lineWidth: row == 2 ? 1.2 : 0.7)
            }

            for column in 0...8 {
                let x = size.width * CGFloat(column) / 8
                var line = Path()
                line.move(to: CGPoint(x: x, y: 0))
                line.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(line, with: .color(gridColor), lineWidth: 0.7)
            }

            guard gains.count > 1 else { return }
            var curve = Path()
            for index in gains.indices {
                let x = size.width * CGFloat(index) / CGFloat(gains.count - 1)
                let normalized = CGFloat(max(-12, min(12, gains[index])) / 12)
                let y = middleY - normalized * size.height * 0.42
                if index == gains.startIndex {
                    curve.move(to: CGPoint(x: x, y: y))
                } else {
                    curve.addLine(to: CGPoint(x: x, y: y))
                }
            }
            context.stroke(
                curve,
                with: .color(PlayerPalette.green),
                style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round)
            )
        }
        .background(PlayerPalette.background.opacity(0.72))
        .cornerRadius(6)
        .accessibilityLabel("实时 EQ 曲线")
    }
}
