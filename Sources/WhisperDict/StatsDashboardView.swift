import AppKit

/// The Stats tab content: metric tiles, a 30-day activity trend, and a
/// languages / top-apps / top-commands row. All data is local.
@MainActor
final class StatsDashboardView: NSView {
    private let wordsTile = MetricTile(caption: "words")
    private let dictationsTile = MetricTile(caption: "dictations")
    private let wpmTile = MetricTile(caption: "words/min")
    private let savedTile = MetricTile(caption: "min saved")
    private let trend = BarTrendView()
    private let donut = DonutView()
    private let apps = HBarListView()
    private let commands = HBarListView()
    private let emptyLabel = NSTextField(labelWithString: "No dictations yet.")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
        refresh()
    }
    required init?(coder: NSCoder) { fatalError() }

    func refresh() {
        let dictations = StatsStore.totalDictations
        emptyLabel.isHidden = dictations != 0
        wordsTile.value = "\(StatsStore.totalWords)"
        dictationsTile.value = "\(dictations)"
        wpmTile.value = "\(StatsStore.wordsPerMinute())"
        savedTile.value = "\(StatsStore.minutesSaved())"
        trend.data = StatsStore.last30Days().map { $0.words }
        donut.segments = StatsStore.topLanguages(limit: 3).map { (label: $0.language.uppercased(), value: $0.count) }
        let topApps = StatsStore.topApps(limit: 4)
        apps.rows = topApps.map { (label: Self.appName(for: $0.bundleID), value: $0.words) }
        apps.icons = topApps.map { Self.appIcon(for: $0.bundleID) }
        commands.rows = StatsStore.topCommands(limit: 4).map { (label: $0.command, value: $0.count) }
    }

    private func build() {
        let tiles = NSStackView(views: [wordsTile, dictationsTile, wpmTile, savedTile])
        tiles.orientation = .horizontal
        tiles.distribution = .fillEqually
        tiles.spacing = 10

        let trendTitle = sectionTitle("Activity — last 30 days")
        trend.translatesAutoresizingMaskIntoConstraints = false
        trend.heightAnchor.constraint(equalToConstant: 48).isActive = true

        let langCol = labeledColumn("Languages", donut)
        let appsCol = labeledColumn("Top apps", apps)
        let cmdCol = labeledColumn("Commands", commands)
        let columns = NSStackView(views: [langCol, appsCol, cmdCol])
        columns.orientation = .horizontal
        columns.distribution = .fillEqually
        columns.alignment = .top
        columns.spacing = 16

        emptyLabel.font = .systemFont(ofSize: 12)
        emptyLabel.textColor = .secondaryLabelColor

        let root = NSStackView(views: [tiles, trendTitle, trend, columns, emptyLabel])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 18
        root.translatesAutoresizingMaskIntoConstraints = false
        addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: topAnchor),
            root.leadingAnchor.constraint(equalTo: leadingAnchor),
            root.trailingAnchor.constraint(equalTo: trailingAnchor),
            root.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
            tiles.widthAnchor.constraint(equalTo: root.widthAnchor),
            trend.widthAnchor.constraint(equalTo: root.widthAnchor),
            columns.widthAnchor.constraint(equalTo: root.widthAnchor),
        ])
    }

    private func sectionTitle(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: 11, weight: .semibold)
        l.textColor = .secondaryLabelColor
        return l
    }

    private func labeledColumn(_ title: String, _ content: NSView) -> NSView {
        let col = NSStackView(views: [sectionTitle(title), content])
        col.orientation = .vertical
        col.alignment = .leading
        col.spacing = 8
        return col
    }

    private static func appName(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
    private static func appIcon(for bundleID: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 16, height: 16)
        return icon
    }
}
