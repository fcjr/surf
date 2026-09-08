import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Per-button configuration. The remote on the left lights up as you press it, which selects
/// the matching row; each row picks what that button does.
struct ButtonsView: View {
    @Environment(RemoteStore.self) private var store
    @State private var selected: RemoteButton? = .click
    @State private var recording: RemoteButton?
    @State private var monitor: Any?

    private var pressed: ButtonSet {
        var lit = store.paired.first { $0.isConnected }?.pressed ?? []
        if !lit.isDisjoint(with: .ring) { lit.remove(.click) }  // a rim press is a direction, not a center press
        return lit
    }

    var body: some View {
        HStack(alignment: .top, spacing: 28) {
            RemoteDiagram(selected: $selected, pressed: pressed)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 4) {
                Text("Press a button on the remote to find it, or click one on the left.")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.bottom, 6)
                ForEach(RemoteButton.allCases) { b in
                    row(b, action: binding(for: b))
                }
                Spacer(minLength: 12)
                HStack {
                    Spacer()
                    Button("Reset to defaults") { store.resetButtonActions() }
                }
            }
            .frame(width: 380)
        }
        .padding(20)
        .onChange(of: pressed) { old, new in
            if let b = RemoteButton.allCases.first(where: { new.contains($0.bit) && !old.contains($0.bit) }) { selected = b }
        }
        .onChange(of: recording) { _, r in r == nil ? stopRecording() : startRecording() }
        .onDisappear { recording = nil }
    }

    private func binding(for b: RemoteButton) -> Binding<ButtonAction> {
        Binding(get: { store.buttonActions[b] ?? b.defaultAction }, set: { store.buttonActions[b] = $0 })
    }

    private func row(_ b: RemoteButton, action: Binding<ButtonAction>) -> some View {
        HStack(spacing: 8) {
            Text(b.title).frame(width: 100, alignment: .leading)
            if recording == b {
                Text("Press a key combination…").foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { recording = nil }.controlSize(.small)
            } else {
                Picker("", selection: action) {
                    if b.isSystem {
                        Text(ButtonAction.system.title).tag(ButtonAction.system)
                        Divider()
                    }
                    ForEach(Array(ButtonAction.presets.enumerated()), id: \.offset) { i, group in
                        if i > 0 { Divider() }
                        ForEach(group, id: \.self) { Text($0.title).tag($0) }
                    }
                    if !ButtonAction.presets.joined().contains(action.wrappedValue) {
                        Divider()
                        Text(action.wrappedValue.title).tag(action.wrappedValue)
                    }
                }
                .labelsHidden()
                Button { recording = b; selected = b } label: { Image(systemName: "keyboard") }
                    .controlSize(.small)
                    .help("Record a custom shortcut")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(selected == b ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 7))
        .contentShape(Rectangle())
        .onTapGesture { selected = b }
    }

    private func startRecording() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { ev in
            let flags = (ev.cgEvent?.flags ?? []).intersection(KeyCombo.modifierMask)
            if let b = recording, !(Int(ev.keyCode) == kVK_Escape && flags.isEmpty) {
                store.buttonActions[b] = .key(KeyCombo(Int(ev.keyCode), flags))
            }
            recording = nil
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

/// A front view of the remote. Buttons highlight when pressed on the real remote and when selected.
struct RemoteDiagram: View {
    @Binding var selected: RemoteButton?
    let pressed: ButtonSet

    private let pad = CGPoint(x: 58, y: 92)

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 32)
                .fill(LinearGradient(colors: [Color(white: 0.30), Color(white: 0.18)], startPoint: .top, endPoint: .bottom))
                .frame(width: 116, height: 440)
                .overlay(RoundedRectangle(cornerRadius: 32).strokeBorder(Color.white.opacity(0.12)))

            button(.power, at: CGPoint(x: 90, y: 20)) { circle(22, "power") }
            ring(.up, from: -135, to: -45)
            ring(.right, from: -45, to: 45)
            ring(.down, from: 45, to: 135)
            ring(.left, from: 135, to: 225)
            button(.click, at: pad) { Circle().frame(width: 60, height: 60) }
            button(.siri, at: CGPoint(x: 119, y: 94)) {
                Capsule().frame(width: 7, height: 50)
            }

            button(.back, at: CGPoint(x: 34, y: 164)) { circle(38, "chevron.left") }
            button(.tv, at: CGPoint(x: 82, y: 164)) { circle(38, "tv") }
            button(.playPause, at: CGPoint(x: 34, y: 214)) { circle(38, "playpause.fill") }
            // spans the height of Play/Pause and Mute together, top edge to bottom edge
            button(.volumeUp, at: CGPoint(x: 82, y: 217)) { rocker("plus", top: true) }
            button(.volumeDown, at: CGPoint(x: 82, y: 261)) { rocker("minus", top: false) }
            button(.mute, at: CGPoint(x: 34, y: 264)) { circle(38, "speaker.slash.fill") }
        }
        .frame(width: 124, height: 440)
    }

    private func ring(_ b: RemoteButton, from: Double, to: Double) -> some View {
        button(b, at: pad) {
            Arc(start: .degrees(from), end: .degrees(to), inner: 31, outer: 49)
                .frame(width: 98, height: 98)
        }
    }

    private func circle(_ size: CGFloat, _ symbol: String) -> some View {
        Circle().frame(width: size, height: size)
            .overlay(Image(systemName: symbol).font(.system(size: size * 0.4, weight: .semibold)).foregroundStyle(.black.opacity(0.7)))
    }

    private func rocker(_ symbol: String, top: Bool) -> some View {
        UnevenRoundedRectangle(topLeadingRadius: top ? 19 : 0, bottomLeadingRadius: top ? 0 : 19,
                               bottomTrailingRadius: top ? 0 : 19, topTrailingRadius: top ? 19 : 0)
            .frame(width: 38, height: 44)
            .overlay(Image(systemName: symbol).font(.system(size: 13, weight: .bold)).foregroundStyle(.black.opacity(0.7)))
    }

    private func button<S: View>(_ b: RemoteButton, at p: CGPoint, @ViewBuilder shape: () -> S) -> some View {
        let lit = pressed.contains(b.bit)
        let fill: Color = lit ? .accentColor : Color(white: 0.5)
        return shape()
            .foregroundStyle(fill)
            .overlay {
                if selected == b { shape().foregroundStyle(.clear).overlay(Color.accentColor.opacity(0.35)).mask(shape()) }
            }
            .animation(.easeOut(duration: 0.12), value: lit)
            .position(p)
            .onTapGesture { selected = b }
            .help(b.title)
    }
}

/// A slice of a ring, for the clickpad's directional zones.
struct Arc: Shape {
    let start: Angle
    let end: Angle
    let inner: CGFloat
    let outer: CGFloat

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        var p = Path()
        p.addArc(center: c, radius: outer, startAngle: start, endAngle: end, clockwise: false)
        p.addArc(center: c, radius: inner, startAngle: end, endAngle: start, clockwise: true)
        p.closeSubpath()
        return p
    }
}
