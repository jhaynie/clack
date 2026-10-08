import SwiftUI

private let accent = Color(red: 1, green: 0.63, blue: 0.36)

struct MenuView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image(systemName: "waveform").font(.system(size: 22, weight: .medium)).foregroundStyle(accent)
                    .frame(width: 42, height: 42).background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Clack").font(.system(size: 23, weight: .semibold, design: .rounded))
                    Text("Holy Panda · Deep thock").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Circle().fill(state.enabled && state.listening && state.audioError == nil ? accent : Color.secondary)
                    .frame(width: 7, height: 7)
            }

            KeyboardPicture(active: state.enabled, previewing: state.previewing)
                .frame(height: 97).padding(12)
                .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Keyboard sounds").font(.system(size: 14, weight: .medium))
                    Text(status).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Keyboard sounds", isOn: $state.enabled).labelsHidden().toggleStyle(.switch).tint(accent)
            }

            if !state.hasPermission {
                VStack(alignment: .leading, spacing: 9) {
                    Label("One quick setup", systemImage: "hand.raised").font(.system(size: 12, weight: .semibold))
                    Text("Allow Clack in Input Monitoring to hear keys in every app. If it is already enabled but not working, remove Clack from the list and add it again, then reopen Clack.")
                        .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Button("Open Input Monitoring") { state.requestPermission() }
                        .buttonStyle(.borderedProminent).tint(accent).foregroundStyle(.black)
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
            }

            VStack(spacing: 14) {
                settingSlider("Volume", symbol: "speaker.wave.2", value: $state.volume)
                settingSlider("Spatial width", symbol: "ear.badge.waveform", value: $state.spatial)
            }
            Toggle("Key release sounds", isOn: $state.releases)
                .font(.system(size: 12)).toggleStyle(.switch).controlSize(.small).tint(accent)

            HStack {
                Button { state.preview() } label: {
                    Label(state.previewing ? "Playing…" : "Preview", systemImage: "play.fill")
                        .font(.system(size: 12, weight: .medium))
                }.buttonStyle(.bordered).disabled(!state.enabled || state.previewing || state.audioError != nil)
                Spacer()
                Text("Best with wired headphones").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            if let error = state.audioError {
                VStack(alignment: .leading, spacing: 6) {
                    Text(error).font(.system(size: 11)).foregroundStyle(accent).fixedSize(horizontal: false, vertical: true)
                    Button("Retry Audio") { state.retryAudio() }.font(.system(size: 11))
                }
            }

            Divider().opacity(0.5)
            Toggle("Launch at login", isOn: Binding(get: { state.loginEnabled }, set: { state.setLoginEnabled($0) }))
                .font(.system(size: 12)).toggleStyle(.switch).controlSize(.small).tint(accent)
            if state.loginNeedsApproval {
                Button("Approve in Login Items…") { state.openLoginSettings() }.font(.system(size: 11))
            }
            if let error = state.loginError {
                Text("Login item: \(error)").font(.system(size: 11)).foregroundStyle(accent)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Text("No keystrokes stored").font(.system(size: 10)).foregroundStyle(.tertiary)
                Spacer()
                Menu {
                    Button("Input Monitoring Settings…") { state.openInputSettings() }
                    Button("Retry Audio") { state.retryAudio() }
                    Button("About Clack") { NSApp.orderFrontStandardAboutPanel() }
                    Divider()
                    Button("Quit Clack") { NSApp.terminate(nil) }.keyboardShortcut("q")
                } label: { Image(systemName: "ellipsis.circle").font(.system(size: 16)) }
                    .menuStyle(.borderlessButton).fixedSize()
            }
        }.padding(22).frame(width: 352).preferredColorScheme(.dark)
            .background(Color(red: 0.095, green: 0.105, blue: 0.115))
    }

    private var status: String {
        if !state.enabled { return "Paused" }
        if state.audioError != nil { return "Audio needs attention" }
        if !state.hasPermission { return "Waiting for Input Monitoring" }
        if !state.listening { return "Connecting to your keyboard…" }
        return "Listening across your Mac"
    }

    private func settingSlider(_ title: String, symbol: String, value: Binding<Double>) -> some View {
        VStack(spacing: 6) {
            HStack {
                Label(title, systemImage: symbol).font(.system(size: 12))
                Spacer()
                Text("\(Int(value.wrappedValue * 100))%").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
            }
            Slider(value: value, in: 0...1).tint(accent).controlSize(.small).accessibilityLabel(title)
        }
    }
}

private struct KeyboardPicture: View {
    let active: Bool
    let previewing: Bool
    var body: some View {
        Canvas { context, size in
            let gap: CGFloat = 3, height: CGFloat = 17
            let unit = (size.width - gap * 13) / 14
            let rows: [[CGFloat]] = [Array(repeating: 1, count: 14),
                [1.5] + Array(repeating: 1, count: 11) + [1.5],
                [1.75] + Array(repeating: 1, count: 10) + [2.25],
                [2.25] + Array(repeating: 1, count: 9) + [2.75],
                [1.5,1.25,1.25,6,1.25,1.25,1.5]]
            for (row, keys) in rows.enumerated() {
                var x: CGFloat = 0
                for (column, width) in keys.enumerated() {
                    let rect = CGRect(x: x, y: CGFloat(row) * (height + gap), width: width * unit + (width - 1) * gap, height: height)
                    let path = Path(roundedRect: rect, cornerRadius: 3)
                    let highlighted = active && ((row == 2 && column >= 3 && column <= 7) || (row == 4 && column == 3))
                    context.fill(path, with: .color(highlighted ? accent.opacity(previewing ? 0.8 : 0.28) : .white.opacity(0.07)))
                    context.stroke(path, with: .color(highlighted ? accent.opacity(0.5) : .white.opacity(0.10)), lineWidth: 0.6)
                    x += rect.width + gap
                }
            }
        }.accessibilityLabel("Mechanical keyboard illustration")
    }
}
