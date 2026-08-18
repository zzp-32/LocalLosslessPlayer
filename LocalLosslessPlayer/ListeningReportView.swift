import Charts
import SwiftUI

struct ListeningReportView: View {
    @EnvironmentObject private var player: PlayerViewModel
    @ObservedObject var library: LibraryViewModel
    @ObservedObject private var history = ListeningHistoryStore.shared
    let onPlay: (Song) -> Void

    @State private var period: ListeningPeriod = .day
    @State private var anchor = Date()
    @State private var summary = ListeningReportSummary.empty(for: .day, anchor: Date())

    var body: some View {
        ZStack {
            AlbumArtworkBackground(artworkPath: player.currentSong?.artworkPath, emphasis: true)
            ScrollView {
                VStack(spacing: 22) {
                    periodPicker
                    periodNavigation
                    overviewSection
                    chartSection
                    rankingSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 30)
            }
        }
        .navigationTitle("听歌报告")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(PlayerPalette.background.opacity(0.94), for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
        .task(id: ReportRequest(period: period, anchor: anchor, revision: history.revision)) {
            let result = await history.summaryAsync(for: period, anchor: anchor)
            guard !Task.isCancelled else { return }
            summary = result
        }
    }

    private var periodPicker: some View {
        HStack(spacing: 0) {
            ForEach(ListeningPeriod.allCases) { item in
                Button {
                    period = item
                    anchor = Date()
                } label: {
                    Text(item.rawValue)
                        .font(.system(size: 15, weight: period == item ? .semibold : .regular))
                        .foregroundStyle(period == item ? PlayerPalette.background : PlayerPalette.secondary)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background(period == item ? PlayerPalette.green : Color.clear)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(PlayerPalette.surface.opacity(0.94))
        .cornerRadius(8)
    }

    private var periodNavigation: some View {
        HStack {
            Button { movePeriod(-1) } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 44, height: 40)
            }
            .buttonStyle(.plain)
            .foregroundStyle(PlayerPalette.secondary)

            Spacer()
            Text(periodTitle)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(PlayerPalette.primary)
            Spacer()

            Button { movePeriod(1) } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 44, height: 40)
            }
            .buttonStyle(.plain)
            .foregroundStyle(canMoveForward ? PlayerPalette.secondary : PlayerPalette.secondary.opacity(0.25))
            .disabled(!canMoveForward)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 28)
                .onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height) * 1.3 else { return }
                    if value.translation.width > 45 {
                        movePeriod(-1)
                    } else if value.translation.width < -45, canMoveForward {
                        movePeriod(1)
                    }
                }
        )
    }

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("统计概览", icon: "waveform.path.ecg")
            HStack(spacing: 0) {
                metric(title: "听歌时长", value: durationText(summary.totalListenedSeconds))
                divider
                metric(title: "播放次数", value: "\(summary.validPlayCount) 次")
            }
            HStack(spacing: 0) {
                metric(title: "播放歌曲", value: "\(summary.playbackSessions) 首")
                divider
                metric(title: "实际歌曲", value: "\(summary.uniqueSongs) 首")
            }
        }
        .padding(18)
        .background(PlayerPalette.surface.opacity(0.9))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(PlayerPalette.line))
    }

    private var divider: some View {
        Rectangle()
            .fill(PlayerPalette.line)
            .frame(width: 1, height: 48)
    }

    private func metric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption)
                .foregroundStyle(PlayerPalette.secondary)
            Text(value)
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(PlayerPalette.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
    }

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("听歌统计", icon: "chart.bar.fill")
            ZStack {
                Chart(summary.chartPoints) { point in
                    BarMark(
                        x: .value("时间", point.date, unit: chartUnit),
                        y: .value("分钟", point.listenedSeconds / 60)
                    )
                    .foregroundStyle(PlayerPalette.green)
                    .cornerRadius(2)
                }
                .chartXAxis {
                    AxisMarks(values: axisDates) { value in
                        AxisGridLine().foregroundStyle(Color.white.opacity(0.05))
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(axisLabel(date))
                                    .font(.system(size: 10))
                                    .foregroundStyle(PlayerPalette.secondary)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine().foregroundStyle(Color.white.opacity(0.08))
                        AxisValueLabel {
                            if let number = value.as(Double.self) {
                                Text(number < 1 ? String(format: "%.1f", number) : "\(Int(number))")
                                    .font(.system(size: 10))
                                    .foregroundStyle(PlayerPalette.secondary)
                            }
                        }
                    }
                }
                .chartYScale(domain: 0...chartMaximum)
                .frame(height: 210)

                if summary.totalListenedSeconds < 0.5 {
                    Text("当前时间范围暂无记录")
                        .font(.subheadline)
                        .foregroundStyle(PlayerPalette.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(PlayerPalette.raised.opacity(0.9))
                        .cornerRadius(6)
                }
            }
        }
        .padding(18)
        .background(PlayerPalette.surface.opacity(0.88))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(PlayerPalette.line))
    }

    @ViewBuilder
    private var rankingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("播放歌曲", icon: "music.note.list")
                .padding(.horizontal, 2)

            if summary.songs.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "music.note")
                        .font(.system(size: 30))
                        .foregroundStyle(PlayerPalette.green)
                    Text("还没有听歌记录")
                        .font(.headline)
                        .foregroundStyle(PlayerPalette.primary)
                    Text("开始播放音乐后，这里会记录你的听歌数据。")
                        .font(.subheadline)
                        .foregroundStyle(PlayerPalette.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 38)
            } else {
                let songLookup = Dictionary(
                    library.songs.map { ($0.checksum, $0) },
                    uniquingKeysWith: { first, _ in first }
                )
                VStack(spacing: 0) {
                    ForEach(summary.songs) { ranking in
                        rankingRow(ranking, song: songLookup[ranking.checksum])
                        if ranking.id != summary.songs.last?.id {
                            Divider().overlay(PlayerPalette.line).padding(.leading, 68)
                        }
                    }
                }
                .background(PlayerPalette.surface.opacity(0.86))
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(PlayerPalette.line))
            }
        }
    }

    private func rankingRow(_ ranking: ListeningSongRanking, song: Song?) -> some View {
        return Button {
            guard let song else { return }
            onPlay(song)
        } label: {
            HStack(spacing: 12) {
                ArtworkTile(
                    title: ranking.title,
                    size: 48,
                    artworkPath: song?.artworkPath ?? ranking.artworkPath
                )
                VStack(alignment: .leading, spacing: 4) {
                    Text(ranking.title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(PlayerPalette.primary)
                        .lineLimit(1)
                    Text(ranking.artist.nilIfEmpty ?? "未知艺术家")
                        .font(.caption)
                        .foregroundStyle(PlayerPalette.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text("\(ranking.playCount) 次")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(PlayerPalette.green)
            }
            .padding(.horizontal, 14)
            .frame(height: 70)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(song == nil)
        .opacity(song == nil ? 0.55 : 1)
    }

    private func sectionTitle(_ title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(PlayerPalette.green)
            Text(title)
                .font(.headline)
                .foregroundStyle(PlayerPalette.primary)
        }
    }

    private var chartUnit: Calendar.Component {
        switch period {
        case .day: return .hour
        case .week, .month: return .day
        case .year: return .month
        }
    }

    private var axisDates: [Date] {
        let points = summary.chartPoints
        switch period {
        case .day:
            return points.enumerated().compactMap { $0.offset % 4 == 0 ? $0.element.date : nil }
        case .week, .year:
            return points.map(\.date)
        case .month:
            return points.enumerated().compactMap { index, point in
                (index == 0 || (index + 1) % 5 == 0 || index == points.count - 1) ? point.date : nil
            }
        }
    }

    private var chartMaximum: Double {
        max(1, (summary.chartPoints.map(\.listenedSeconds).max() ?? 0) / 60 * 1.18)
    }

    private var periodTitle: String {
        let interval = summary.interval
        switch period {
        case .day:
            return formattedDate(interval.start, format: "yyyy年M月d日")
        case .week:
            let end = interval.end.addingTimeInterval(-1)
            return "\(formattedDate(interval.start, format: "M月d日")) - \(formattedDate(end, format: "M月d日"))"
        case .month:
            return formattedDate(interval.start, format: "yyyy年M月")
        case .year:
            return formattedDate(interval.start, format: "yyyy年")
        }
    }

    private var canMoveForward: Bool {
        guard let next = Calendar.autoupdatingCurrent.date(
            byAdding: period.calendarComponent,
            value: 1,
            to: anchor
        ) else { return false }
        return next <= Date()
    }

    private func movePeriod(_ value: Int) {
        guard value < 0 || canMoveForward else { return }
        if let date = Calendar.autoupdatingCurrent.date(
            byAdding: period.calendarComponent,
            value: value,
            to: anchor
        ) {
            anchor = date
        }
    }

    private func axisLabel(_ date: Date) -> String {
        switch period {
        case .day: return formattedDate(date, format: "HH")
        case .week: return formattedDate(date, format: "EEE")
        case .month: return formattedDate(date, format: "d")
        case .year: return formattedDate(date, format: "M月")
        }
    }

    private func formattedDate(_ date: Date, format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    private func durationText(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        if total < 60 { return "\(total) 秒" }
        let minutes = total / 60
        if minutes < 60 { return "\(minutes) 分钟" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours) 小时" : "\(hours)小时 \(remainder)分"
    }
}

private struct ReportRequest: Hashable {
    let period: ListeningPeriod
    let anchor: Date
    let revision: Int
}

private extension ListeningReportSummary {
    static func empty(for period: ListeningPeriod, anchor: Date) -> ListeningReportSummary {
        let interval = Calendar.autoupdatingCurrent.dateInterval(of: period.calendarComponent, for: anchor)
            ?? DateInterval(start: anchor, duration: 1)
        return ListeningReportSummary(
            interval: interval,
            totalListenedSeconds: 0,
            playbackSessions: 0,
            uniqueSongs: 0,
            validPlayCount: 0,
            chartPoints: [],
            songs: []
        )
    }
}
