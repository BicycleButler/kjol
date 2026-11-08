import SwiftUI
import AppKit
import Foundation
import Combine
import ServiceManagement
import Darwin

enum Design {
    enum Spacing {
        static let space1: CGFloat = 4
        static let space2: CGFloat = 8
        static let space3: CGFloat = 12
        static let space4: CGFloat = 16
        static let space6: CGFloat = 24
        static let space8: CGFloat = 32
        static let space12: CGFloat = 48
    }

    enum Typography {
        static let xs = Font.system(size: 11, weight: .regular)
        static let sm = Font.system(size: 13, weight: .medium)
        static let base = Font.system(size: 15, weight: .semibold)
        static let lg = Font.system(size: 18, weight: .bold)

        static let xsMono = Font.system(size: 11, weight: .regular, design: .monospaced)
        static let smMono = Font.system(size: 13, weight: .medium, design: .monospaced)
    }

    enum Color {
        static let background = SwiftUI.Color(NSColor.windowBackgroundColor)
        static let cardBackground = SwiftUI.Color(NSColor.controlBackgroundColor)
        static let foreground = SwiftUI.Color.primary
        static let secondaryText = SwiftUI.Color.secondary
        static let tertiaryText = SwiftUI.Color.secondary.opacity(0.6)
        static let warning = SwiftUI.Color.orange
        static let accent = SwiftUI.Color.accentColor
    }

    enum Icon {
        static let inline: CGFloat = 14
        static let action: CGFloat = 18
        static let nav: CGFloat = 22
    }
}

enum TooltipPlacement {
    case top
    case bottom
}

final class TooltipCoordinator: ObservableObject {
    @Published var activeTooltip: TooltipData? = nil
    private var pendingWorkItem: DispatchWorkItem?

    struct TooltipData: Equatable {
        let title: String
        let description: String
        let targetFrame: CGRect
        let placement: TooltipPlacement
    }

    func show(title: String, description: String, frame: CGRect, placement: TooltipPlacement, delay: Double = 0.2) {
        pendingWorkItem?.cancel()
        let effectiveDelay = activeTooltip != nil ? 0.05 : delay
        let item = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            withAnimation(.easeInOut(duration: 0.12)) {
                self.activeTooltip = TooltipData(
                    title: title,
                    description: description,
                    targetFrame: frame,
                    placement: placement
                )
            }
        }
        pendingWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + effectiveDelay, execute: item)
    }

    func hide() {
        pendingWorkItem?.cancel()
        pendingWorkItem = nil
        if activeTooltip != nil {
            withAnimation(.easeInOut(duration: 0.08)) {
                activeTooltip = nil
            }
        }
    }
}

struct TooltipFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero {
            value = next
        }
    }
}

struct TooltipBubbleSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next != .zero {
            value = next
        }
    }
}

struct ActiveTooltipOverlay: View {
    let tooltip: TooltipCoordinator.TooltipData
    @State private var bubbleSize: CGSize = CGSize(width: 180, height: 42)

    var body: some View {
        guard tooltip.targetFrame.width > 0 && tooltip.targetFrame.height > 0 else {
            return AnyView(EmptyView())
        }

        let isTop = tooltip.placement == .top ||
            (tooltip.targetFrame.maxY + bubbleSize.height + 12 > 570 && tooltip.targetFrame.minY > bubbleSize.height + 12)
        let targetMidX = tooltip.targetFrame.midX
        // Clamp X so bubble stays strictly within the 513pt window with 8pt margin
        let clampedX = min(max(targetMidX - bubbleSize.width / 2, 8), 505 - bubbleSize.width)
        let computedY = isTop
            ? (tooltip.targetFrame.minY - bubbleSize.height - 6)
            : (tooltip.targetFrame.maxY + 6)

        return AnyView(
            VStack(alignment: .leading, spacing: 2) {
                Text(tooltip.title)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(SwiftUI.Color.white)
                if !tooltip.description.isEmpty {
                    Text(tooltip.description)
                        .font(.system(size: 9.5, weight: .regular))
                        .foregroundStyle(SwiftUI.Color.white.opacity(0.88))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: 240, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(SwiftUI.Color(NSColor.black).opacity(0.94))
                    .shadow(color: SwiftUI.Color.black.opacity(0.35), radius: 6, x: 0, y: 3)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(SwiftUI.Color.white.opacity(0.2), lineWidth: 0.5)
            )
            .background(
                GeometryReader { geo in
                    SwiftUI.Color.clear
                        .preference(key: TooltipBubbleSizeKey.self, value: geo.size)
                }
            )
            .onPreferenceChange(TooltipBubbleSizeKey.self) { newSize in
                if newSize.width > 0 && newSize.height > 0 {
                    self.bubbleSize = newSize
                }
            }
            .offset(x: clampedX, y: max(6, computedY))
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
        )
    }
}

struct KjolTooltipModifier: ViewModifier {
    let title: String
    let description: String
    var placement: TooltipPlacement = .bottom
    var delay: Double = 0.2

    @EnvironmentObject private var tooltipCoordinator: TooltipCoordinator
    @State private var globalFrame: CGRect = .zero

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geo in
                    SwiftUI.Color.clear
                        .preference(key: TooltipFramePreferenceKey.self, value: geo.frame(in: .named("kjolWindowSpace")))
                }
            )
            .onPreferenceChange(TooltipFramePreferenceKey.self) { frame in
                self.globalFrame = frame
            }
            .onHover { hovering in
                if hovering {
                    tooltipCoordinator.show(
                        title: title,
                        description: description,
                        frame: globalFrame,
                        placement: placement,
                        delay: delay
                    )
                } else {
                    tooltipCoordinator.hide()
                }
            }
    }
}

extension View {
    func kjolTooltip(title: String, description: String = "", placement: TooltipPlacement = .bottom) -> some View {
        modifier(KjolTooltipModifier(title: title, description: description, placement: placement))
    }
}

enum FanProfile: String, CaseIterable, Identifiable {
    case auto, adaptive, manual, blast
    var id: String { rawValue }
    var title: String {
        switch self {
        case .auto: return "Auto"
        case .adaptive: return "Adaptive"
        case .manual: return "Manual"
        case .blast: return "Blast"
        }
    }
    var icon: String {
        switch self {
        case .auto: return "sparkles"
        case .adaptive: return "waveform.path.ecg"
        case .manual: return "slider.horizontal.3"
        case .blast: return "flame.fill"
        }
    }
    var badgeText: String {
        switch self {
        case .auto: return "Native"
        case .adaptive: return "Dynamic"
        case .manual: return "Fixed"
        case .blast: return "100%"
        }
    }
}

enum AdaptiveSubProfile: String, CaseIterable, Identifiable {
    case gentle, aggressive, custom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .gentle: return "Gentle"
        case .aggressive: return "Compute"
        case .custom: return "Custom"
        }
    }
    var icon: String {
        switch self {
        case .gentle: return "leaf.fill"
        case .aggressive: return "bolt.fill"
        case .custom: return "chart.xyaxis.line"
        }
    }
    var summary: String {
        switch self {
        case .gentle: return "Cool Native • Whisper quiet with +15% cooling headroom"
        case .aggressive: return "Heavy Compute • Proactive thermal acceleration & peak hold"
        case .custom: return "Interactive Multi-Point Thermal Curve"
        }
    }
}

enum SystemPreset: String, CaseIterable, Identifiable {
    case maxCompute, gentle, none
    var id: String { rawValue }
    var title: String {
        switch self {
        case .maxCompute: return "Max Compute"
        case .gentle: return "Gentle Silent"
        case .none: return "Custom"
        }
    }
    var icon: String {
        switch self {
        case .maxCompute: return "bolt.fill"
        case .gentle: return "leaf.fill"
        case .none: return "slider.horizontal.3"
        }
    }
    var badge: String {
        switch self {
        case .maxCompute: return "Full Turbo • Dynamic Fans"
        case .gentle: return "Low Power • <25% Fans • <75°C"
        case .none: return "Manual / Custom Settings"
        }
    }
}

enum ThermalSafetyPolicy: String, CaseIterable, Identifiable {
    case off, boostFans, throttleCPU
    var id: String { rawValue }
    var title: String {
        switch self {
        case .off: return "Off"
        case .boostFans: return "Fan Boost"
        case .throttleCPU: return "Throttle CPU"
        }
    }
    var icon: String {
        switch self {
        case .off: return "shield.slash"
        case .boostFans: return "wind"
        case .throttleCPU: return "gauge.with.dots.needle.50percent"
        }
    }
    var summary: String {
        switch self {
        case .off: return "Passive SMC failsafes only"
        case .boostFans: return "Performance Priority • Reverts fans to native SMC if ceiling is breached"
        case .throttleCPU: return "Acoustic Priority • Engages Low Power Mode to contain heat and preserve silence"
        }
    }
}

struct CurveMilestone: Identifiable, Equatable, Codable {
    var id: Int { Int(temp) }
    var temp: Double
    var rpmPercent: Double
    var label: String
}

struct FanReading: Equatable, Identifiable {
    var index: Int
    var actualRPM: Double
    var targetRPM: Double
    var minRPM: Double
    var maxRPM: Double
    var mode: Int
    var id: Int { index }
}

private func kjolQuit() {
    NSApplication.shared.terminate(nil)
}

func loadBundleNSImage(_ name: String) -> NSImage? {
    if let path = Bundle.main.path(forResource: name, ofType: nil) ??
                  Bundle.main.path(forResource: (name as NSString).deletingPathExtension, ofType: (name as NSString).pathExtension) {
        return NSImage(contentsOfFile: path)
    }
    return NSImage(named: name)
}

func bundleImage(_ name: String) -> Image? {
    if let nsImg = loadBundleNSImage(name) {
        return Image(nsImage: nsImg)
    }
    return nil
}

struct CardContainer<Content: View>: View {
    let title: String
    let backgroundResource: String?
    let content: Content

    init(title: String, backgroundResource: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.backgroundResource = backgroundResource
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.space2) {
            Text(title)
                .font(Design.Typography.xs)
                .foregroundStyle(Design.Color.tertiaryText)
            content
        }
        .padding(Design.Spacing.space3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                Design.Color.cardBackground
                if let res = backgroundResource, let img = bundleImage(res) {
                    GeometryReader { geo in
                        img
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                            .opacity(0.18)
                            .blendMode(.luminosity)
                            .overlay(
                                LinearGradient(
                                    colors: [
                                        Design.Color.cardBackground.opacity(0.6),
                                        Design.Color.cardBackground.opacity(0.92)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(SwiftUI.Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

struct HeaderView: View {
    @ObservedObject var host: Host

    var body: some View {
        HStack(spacing: Design.Spacing.space2) {
            // Left: App Motif / Icon & Title
            HStack(spacing: 6) {
                if let motif = bundleImage("clamshell-motif.jpg") {
                    motif
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 18, height: 18)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                } else {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: Design.Icon.action))
                        .foregroundStyle(Design.Color.accent)
                }
                Text("Kjol")
                    .font(Design.Typography.base)
            }

            Spacer(minLength: 8)

            // Right: Busy Indicator & Helper Status Badge
            if host.busy {
                ProgressView()
                    .controlSize(.small)
            }
            Text(host.helperInstalled ? "Active" : "Helper Required")
                .font(Design.Typography.xs)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    host.helperInstalled ? Design.Color.accent.opacity(0.15) : Design.Color.warning.opacity(0.15),
                    in: Capsule()
                )
                .foregroundStyle(host.helperInstalled ? Design.Color.accent : Design.Color.warning)
                .kjolTooltip(
                    title: host.helperInstalled ? "Privileged Helper Active" : "Privileged Helper Required",
                    description: host.helperInstalled
                        ? "Root daemon is connected and active. Managing SMC hardware keys and system power policies."
                        : "Kjol requires the background daemon for privileged hardware operations. Please run the installer package."
                )
        }
    }
}

struct ExpandableSectionHeader: View {
    let title: String
    let icon: String
    let isExpanded: Bool
    let action: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isExpanded ? Design.Color.accent : Design.Color.secondaryText)

                Text(title)
                    .font(Design.Typography.xs)
                    .fontWeight(.medium)
                    .foregroundStyle(isExpanded ? Design.Color.foreground : Design.Color.secondaryText)

                Spacer()

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isExpanded ? Design.Color.accent : Design.Color.tertiaryText)
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(
                isExpanded ? Design.Color.accent.opacity(0.1) : (isHovered ? Design.Color.background : Design.Color.background.opacity(0.6)),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(
                        isExpanded ? Design.Color.accent.opacity(0.4) : (isHovered ? Design.Color.tertiaryText.opacity(0.3) : SwiftUI.Color.primary.opacity(0.06)),
                        lineWidth: 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

struct BatterySettingsLauncher {
    static func openSettings() {
        // 1. Modern macOS 13+ Battery Settings pane extension
        if let url = URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension"),
           NSWorkspace.shared.open(url) {
            return
        }
        // 2. Legacy Preference Pane URL
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.battery"),
           NSWorkspace.shared.open(url) {
            return
        }
        // 3. Fallback to System Settings
        if let url = URL(string: "x-apple.systempreferences:"),
           NSWorkspace.shared.open(url) {
            return
        }
    }
}

struct QuickActionsBarView: View {
    @ObservedObject var powerVM: PowerViewModel
    @ObservedObject var host: Host

    private let buttonSize: CGFloat = 40

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // 1. Always-On Compact Icon Button
            Button(action: {
                powerVM.toggleAlwaysOn(!powerVM.alwaysOn)
            }) {
                Image(systemName: powerVM.alwaysOn ? "cup.and.saucer.fill" : "cup.and.saucer")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(powerVM.alwaysOn ? Design.Color.accent : Design.Color.secondaryText)
                    .frame(width: buttonSize, height: buttonSize)
                    .background(
                        powerVM.alwaysOn ? Design.Color.accent.opacity(0.18) : Design.Color.cardBackground,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(
                                powerVM.alwaysOn ? Design.Color.accent.opacity(0.65) : SwiftUI.Color.primary.opacity(0.08),
                                lineWidth: 1
                            )
                    )
            }
            .buttonStyle(.plain)
            .disabled(host.busy)
            .kjolTooltip(
                title: "Always-On",
                description: "Prevents system sleep and maintains compute and clamshell operation when the lid is closed."
            )

            // 2. Boost Memory Compact Icon Button & Minimalist Governor Sub-Control
            VStack(spacing: 4) {
                Button(action: {
                    powerVM.toggleDaemons(!powerVM.daemonsSuspended)
                }) {
                    Image(systemName: powerVM.daemonsSuspended ? "bolt.badge.automatic.fill" : "bolt.badge.automatic")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(powerVM.daemonsSuspended ? Design.Color.accent : Design.Color.secondaryText)
                        .frame(width: buttonSize, height: buttonSize)
                        .background(
                            powerVM.daemonsSuspended ? Design.Color.accent.opacity(0.18) : Design.Color.cardBackground,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(
                                    powerVM.daemonsSuspended ? Design.Color.accent.opacity(0.65) : SwiftUI.Color.primary.opacity(0.08),
                                    lineWidth: 1
                                )
                        )
                }
                .buttonStyle(.plain)
                .disabled(host.busy)
                .kjolTooltip(
                    title: "Boost Memory",
                    description: "Suspends non-critical background daemons, demotes indexing, and purges RAM buffers to maximize available compute."
                )

                // Minimalist Governor Toggle placed directly below Memory Boost button (no text beside it)
                HStack(spacing: 2) {
                    Toggle("", isOn: Binding(
                        get: { powerVM.daemonsSafetyCeilingEnabled },
                        set: { powerVM.toggleDaemonsSafetyCeiling($0) }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                    .disabled(host.busy)

                    if powerVM.daemonsFailsafeTriggered && !powerVM.daemonsSuspended {
                        Button(action: {
                            powerVM.toggleDaemons(true)
                        }) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(Design.Color.warning)
                        }
                        .buttonStyle(.plain)
                        .kjolTooltip(
                            title: "Governor Failsafe Triggered",
                            description: "Daemons were automatically resumed to protect system stability. Click to re-engage Boost Memory."
                        )
                    }
                }
                .frame(width: buttonSize)
                .kjolTooltip(
                    title: powerVM.daemonsSafetyCeilingEnabled ? "Compute Governor: 4h Limit" : "Compute Governor: Persistent Mode",
                    description: powerVM.daemonsSafetyCeilingEnabled
                        ? "4-hour safety ceiling: Automatically resumes background indexing after 4 hours to avoid task backlogs."
                        : "Persistent Mode: Keeps memory and compute optimizations active indefinitely across multi-day tasks until toggled off."
                )
            }

            // Subtle vertical separator
            Rectangle()
                .fill(SwiftUI.Color.primary.opacity(0.08))
                .frame(width: 1, height: buttonSize)
                .padding(.horizontal, 4)

            // 3. Fan Settings Bar (in the same row, same button size)
            HStack(spacing: 8) {
                Image(systemName: "fanblades.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Design.Color.accent)
                    .frame(height: buttonSize)
                    .kjolTooltip(
                        title: "Cooling Presets",
                        description: "Select system-wide acoustic and thermal performance preset"
                    )

                HStack(spacing: 6) {
                    fanPresetButton(
                        preset: .gentle,
                        icon: "leaf.fill",
                        title: "Gentle Silent",
                        tooltip: "Low Power Mode • Whisper-quiet fans (<25%) • <75°C target"
                    )
                    fanPresetButton(
                        preset: .none, // Custom
                        icon: "slider.horizontal.3",
                        title: "Custom",
                        tooltip: "Manual / Custom thermal curves and user-defined fan targets"
                    )
                    fanPresetButton(
                        preset: .maxCompute,
                        icon: "bolt.fill",
                        title: "Max Compute",
                        tooltip: "Full Turbo compute • Active thermal acceleration & dynamic cooling"
                    )
                }
            }
            .padding(.horizontal, 4)

            Spacer()
        }
    }

    private func fanPresetButton(preset: SystemPreset, icon: String, title: String, tooltip: String) -> some View {
        let isSelected = host.fanControlVM.systemPreset == preset
        return Button(action: {
            withAnimation(.easeInOut(duration: 0.15)) {
                host.fanControlVM.selectSystemPreset(preset)
            }
        }) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: isSelected ? .bold : .medium))
                .frame(width: buttonSize, height: buttonSize)
                .background(
                    isSelected ? Design.Color.accent.opacity(0.18) : Design.Color.cardBackground,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(
                            isSelected ? Design.Color.accent.opacity(0.65) : SwiftUI.Color.primary.opacity(0.08),
                            lineWidth: 1
                        )
                )
                .foregroundStyle(isSelected ? Design.Color.accent : Design.Color.secondaryText)
        }
        .buttonStyle(.plain)
        .disabled(host.busy)
        .kjolTooltip(title: title, description: tooltip)
    }
}

struct TelemetryCardView: View {
    @ObservedObject var telemetryVM: TelemetryViewModel
    @State private var showDetailedTelemetry: Bool = false

    var body: some View {
        CardContainer(title: "System Telemetry") {
            VStack(spacing: Design.Spacing.space2) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: Design.Spacing.space1) {
                        metricRow(
                            label: "SoC Temp",
                            value: socTempDisplay,
                            tipTitle: "SoC Temperature",
                            tipDesc: "Package junction temperature of the Apple Silicon System-on-Chip."
                        )
                        metricRow(
                            label: "CPU Temp",
                            value: cpuTempDisplay,
                            tipTitle: "CPU Temperature",
                            tipDesc: "Filtered average temperature across active Performance and Efficiency cores."
                        )
                        metricRow(
                            label: "GPU Temp",
                            value: gpuTempDisplay,
                            tipTitle: "GPU Temperature",
                            tipDesc: "Junction temperature reading from the integrated graphics silicon cluster."
                        )
                    }
                    Spacer(minLength: Design.Spacing.space2)
                    VStack(alignment: .leading, spacing: Design.Spacing.space1) {
                        metricRow(
                            label: "P-Cores (\(telemetryVM.pCoreCount))",
                            value: pCoreDisplay,
                            tipTitle: "Performance Cores",
                            tipDesc: "Aggregated utilization across \(telemetryVM.pCoreCount) high-performance execution cores."
                        )
                        metricRow(
                            label: "E-Cores (\(telemetryVM.eCoreCount))",
                            value: eCoreDisplay,
                            tipTitle: "Efficiency Cores",
                            tipDesc: "Aggregated utilization across \(telemetryVM.eCoreCount) energy-efficient background cores."
                        )
                        metricRow(
                            label: "Battery",
                            value: batteryDisplay,
                            tipTitle: "Battery State",
                            tipDesc: "Current charge percentage, power source connection, and charging status."
                        )
                    }
                }

                ExpandableSectionHeader(
                    title: "Detailed Metrics",
                    icon: "waveform.path.ecg",
                    isExpanded: showDetailedTelemetry
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showDetailedTelemetry.toggle()
                    }
                }

                if showDetailedTelemetry {
                    VStack(alignment: .leading, spacing: Design.Spacing.space2) {
                        Divider()

                        Text("Per-Core CPU Load")
                            .font(Design.Typography.xs)
                            .foregroundStyle(Design.Color.tertiaryText)

                        if telemetryVM.perCoreUsage.isEmpty {
                            Text("Awaiting CPU sampler data...")
                                .font(Design.Typography.xs)
                                .foregroundStyle(Design.Color.secondaryText)
                        } else {
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 4) {
                                ForEach(0..<telemetryVM.perCoreUsage.count, id: \.self) { idx in
                                    let isPCore = idx < telemetryVM.pCoreCount
                                    let label = isPCore ? "P\(idx + 1)" : "E\(idx - telemetryVM.pCoreCount + 1)"
                                    let usage = telemetryVM.perCoreUsage[idx]
                                    coreMeterRow(label: label, usage: usage, isPCore: isPCore)
                                }
                            }
                        }

                        Divider()

                        Text("Granular Thermal Readings")
                            .font(Design.Typography.xs)
                            .foregroundStyle(Design.Color.tertiaryText)

                        HStack(spacing: 4) {
                            sensorTag(name: "SoC", temp: telemetryVM.socTemp, tipDesc: "System-on-Chip package die temperature sensor.")
                            sensorTag(name: "CPU", temp: telemetryVM.cpuTemp, tipDesc: "Central processing unit cluster thermal diode.")
                            sensorTag(name: "GPU", temp: telemetryVM.gpuTemp, tipDesc: "Graphics cluster thermal diode.")
                            sensorTag(name: "Battery", temp: telemetryVM.batteryTemp, tipDesc: "Battery pack internal thermistor sensor.")
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private func metricRow(label: String, value: String, tipTitle: String, tipDesc: String) -> some View {
        HStack(spacing: Design.Spacing.space1) {
            Text(label)
                .font(Design.Typography.xs)
                .foregroundStyle(Design.Color.secondaryText)
            Spacer(minLength: Design.Spacing.space1)
            Text(value)
                .font(Design.Typography.xsMono)
                .monospacedDigit()
                .foregroundStyle(Design.Color.foreground)
                .frame(minWidth: 44, alignment: .trailing)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(Design.Color.background.opacity(0.4), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        .contentShape(Rectangle())
        .kjolTooltip(title: tipTitle, description: tipDesc)
    }

    private func coreMeterRow(label: String, usage: Double, isPCore: Bool) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(Design.Typography.xsMono)
                .bold()
                .foregroundStyle(isPCore ? Design.Color.accent : Design.Color.warning)
                .frame(width: 20, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(SwiftUI.Color.primary.opacity(0.08))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(isPCore ? Design.Color.accent : Design.Color.warning)
                        .frame(width: max(0, min(geo.size.width, geo.size.width * CGFloat(usage))))
                }
            }
            .frame(height: 6)

            Text(String(format: "%.0f%%", usage * 100))
                .font(Design.Typography.xsMono)
                .foregroundStyle(Design.Color.foreground)
                .frame(width: 30, alignment: .trailing)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .background(Design.Color.background, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        .contentShape(Rectangle())
        .kjolTooltip(
            title: isPCore ? "Performance Core \(label)" : "Efficiency Core \(label)",
            description: "Live CPU utilization for core \(label): \(Int(usage * 100))%."
        )
    }

    private func sensorTag(name: String, temp: Double?, tipDesc: String) -> some View {
        VStack(spacing: 2) {
            Text(name)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Design.Color.tertiaryText)
            Text(temp != nil && temp! > 0 ? String(format: "%.0f°C", temp!) : "—")
                .font(Design.Typography.xsMono)
                .bold()
                .foregroundStyle(Design.Color.foreground)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .background(Design.Color.background, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        .contentShape(Rectangle())
        .kjolTooltip(title: "\(name) Sensor", description: tipDesc)
    }

    private var socTempDisplay: String {
        if let t = telemetryVM.socTemp, t > 0 { return String(format: "%.0f°C", t) }
        return "—"
    }

    private var cpuTempDisplay: String {
        if let t = telemetryVM.cpuTemp, t > 0 { return String(format: "%.0f°C", t) }
        return "—"
    }

    private var gpuTempDisplay: String {
        if let t = telemetryVM.gpuTemp, t > 0 { return String(format: "%.0f°C", t) }
        return "—"
    }

    private var pCoreDisplay: String {
        guard telemetryVM.hasCpuSample else { return "—" }
        return String(format: "%.0f%%", telemetryVM.pCoreUsage * 100)
    }

    private var eCoreDisplay: String {
        guard telemetryVM.hasCpuSample else { return "—" }
        return String(format: "%.0f%%", telemetryVM.eCoreUsage * 100)
    }

    private var batteryDisplay: String {
        let pct = telemetryVM.batteryCharge
        guard pct > 0 else { return "—" }
        let tempStr = telemetryVM.batteryTemp != nil ? " • \(Int(telemetryVM.batteryTemp!))°C" : ""
        if telemetryVM.forcedDischarge {
            return "\(pct)% (Discharging)\(tempStr)"
        } else if telemetryVM.heatProtectionActive {
            return "\(pct)% (Overheated)\(tempStr)"
        } else if telemetryVM.topUpActive {
            return "\(pct)% (Top Up ⚡)\(tempStr)"
        } else if telemetryVM.chargingInhibited {
            return "\(pct)% (Hold)\(tempStr)"
        } else if telemetryVM.isCharging {
            return "\(pct)% ⚡\(tempStr)"
        } else {
            return "\(pct)%\(tempStr)"
        }
    }
}

struct HelperMissingCardView: View {
    @ObservedObject var host: Host

    var body: some View {
        CardContainer(title: "Privileged Helper") {
            VStack(alignment: .leading, spacing: Design.Spacing.space2) {
                Text(host.needsReinstall
                      ? "The helper daemon is out of date. Run the Kjol installer package (.pkg) to update it."
                      : "Kjol requires its background helper daemon to manage SMC hardware keys and system power policies. Please run the Kjol installer package (.pkg).")
                    .font(Design.Typography.xs)
                    .foregroundStyle(Design.Color.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Retry Connection") {
                    host.checkHelperInstalled()
                    host.refresh()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(host.busy)
                .kjolTooltip(title: "Retry Helper Connection", description: "Re-checks LaunchDaemon registration and XPC socket connectivity.")
            }
        }
    }
}

struct FanControlCardView: View {
    @ObservedObject var fanVM: FanControlViewModel
    @ObservedObject var telemetryVM: TelemetryViewModel
    @ObservedObject var host: Host

    private var isManual: Bool {
        fanVM.profile == .manual
    }

    private var isAdaptive: Bool {
        fanVM.profile == .adaptive
    }

    private var effectiveTemp: Double? {
        let s = telemetryVM.socTemp ?? 0
        let c = telemetryVM.cpuTemp ?? 0
        let m = max(s, c)
        return m > 0 ? m : nil
    }

    var body: some View {
        CardContainer(title: "Fan Control Strategy", backgroundResource: "fan-header.jpg") {
            VStack(alignment: .leading, spacing: Design.Spacing.space2) {
                // 1. Thermal Posture (promoted to header area with 200ms tooltips)
                thermalPostureSection

                Divider()
                    .padding(.vertical, 2)

                // 2. Single-Row Segmented Profile Control (Auto, Adaptive, Manual, Blast)
                HStack(spacing: 3) {
                    ForEach(FanProfile.allCases) { profile in
                        fanProfileSegment(profile)
                    }
                }
                .padding(3)
                .background(Design.Color.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(SwiftUI.Color.primary.opacity(0.06), lineWidth: 1)
                )

                // 3. Adaptive Sub-options Section
                if isAdaptive {
                    VStack(alignment: .leading, spacing: 6) {
                        // Sub-profile pills
                        HStack(spacing: 3) {
                            ForEach(AdaptiveSubProfile.allCases) { sub in
                                adaptiveSubProfilePill(sub)
                            }
                        }
                        .padding(2)
                        .background(Design.Color.background.opacity(0.8), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                        // Sub-profile specific view
                        if fanVM.adaptiveSubProfile == .custom {
                            CustomCurveEditorView(
                                fanVM: fanVM,
                                currentTemp: effectiveTemp,
                                disabled: !host.helperInstalled
                            )
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        } else {
                            adaptivePresetCard(fanVM.adaptiveSubProfile)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .padding(.top, 2)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // 4. Manual Fixed Slider Section
                if isManual {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: Design.Spacing.space2) {
                            Text("Fixed Speed Target")
                                .font(Design.Typography.xs)
                                .foregroundStyle(Design.Color.secondaryText)
                            Spacer()
                            Text("\(Int(fanVM.customPercent))%")
                                .font(Design.Typography.xsMono)
                                .monospacedDigit()
                                .bold()
                                .foregroundStyle(Design.Color.foreground)
                        }

                        Slider(
                            value: Binding(
                                get: { fanVM.customPercent },
                                set: { fanVM.setCustomPercent($0) }
                            ),
                            in: 0...100,
                            step: 5,
                            onEditingChanged: { editing in
                                if !editing {
                                    fanVM.setCustomPercent(fanVM.customPercent, immediate: true)
                                }
                            }
                        )
                        .disabled(!host.helperInstalled)
                        .kjolTooltip(
                            title: "Fixed Fan Target",
                            description: "Manually locks all fans to this target percentage speed."
                        )

                        // Quick Snap Chips
                        HStack(spacing: 4) {
                            quickSnapButton(percent: 25)
                            quickSnapButton(percent: 50)
                            quickSnapButton(percent: 75)
                            quickSnapButton(percent: 100)
                        }
                    }
                    .padding(.top, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // 5. Live Per-Fan RPM Status Badges
                if !telemetryVM.fans.isEmpty {
                    Divider()
                        .padding(.vertical, 2)

                    HStack(spacing: Design.Spacing.space2) {
                        ForEach(telemetryVM.fans) { fan in
                            HStack(spacing: 4) {
                                Image(systemName: "fanblades.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(fan.mode == 1 ? Design.Color.accent : Design.Color.secondaryText)
                                Text("Fan \(fan.index + 1):")
                                    .font(Design.Typography.xs)
                                    .foregroundStyle(Design.Color.secondaryText)
                                Text("\(Int(fan.actualRPM))")
                                    .font(Design.Typography.xsMono)
                                    .bold()
                                    .foregroundStyle(Design.Color.foreground)
                                Text("RPM")
                                    .font(Design.Typography.xs)
                                    .foregroundStyle(Design.Color.tertiaryText)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Design.Color.background, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .kjolTooltip(
                                title: "Fan \(fan.index + 1) Tachometer",
                                description: "Actual speed: \(Int(fan.actualRPM)) RPM • Target: \(Int(fan.targetRPM)) RPM • Range: \(Int(fan.minRPM))–\(Int(fan.maxRPM)) RPM • Mode: \(fan.mode == 1 ? "Manual/Controlled" : "Auto/Firmware")"
                            )
                        }
                        Spacer()
                    }
                }
            }
        }
    }

    private var thermalPostureSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("Thermal Posture", systemImage: "shield.lefthalf.filled")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Design.Color.foreground)
                    .kjolTooltip(
                        title: "Thermal Posture",
                        description: "Select active hardware protection policy to govern fans and CPU when heat rises."
                    )
                Spacer()
                if fanVM.isThrottlingEngaged {
                    HStack(spacing: 3) {
                        Circle().fill(SwiftUI.Color.orange).frame(width: 5, height: 5)
                        Text("Throttling Active")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(SwiftUI.Color.orange)
                    }
                    .kjolTooltip(
                        title: "CPU Throttling Active",
                        description: "Low Power Mode has engaged to cool down temperature while preserving silence."
                    )
                } else if fanVM.isFanBoostEngaged {
                    HStack(spacing: 3) {
                        Circle().fill(SwiftUI.Color.cyan).frame(width: 5, height: 5)
                        Text("Fan Boost Active")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(SwiftUI.Color.cyan)
                    }
                    .kjolTooltip(
                        title: "Emergency Fan Boost Active",
                        description: "Fans have reverted to native SMC maximum speeds to cool junction temperatures."
                    )
                }
            }

            // Policy segmented pills (Off, Fan Boost, Throttle CPU) with 200ms tooltips
            HStack(spacing: 3) {
                safetyPolicyPill(
                    .off,
                    tipTitle: "Thermal Posture: Off",
                    tipDesc: "Passive SMC firmware failsafes only. No automatic software intervention."
                )
                safetyPolicyPill(
                    .boostFans,
                    tipTitle: "Thermal Posture: Fan Boost",
                    tipDesc: "Performance Priority: Reverts fans to native SMC emergency speeds if ceiling temperature is breached."
                )
                safetyPolicyPill(
                    .throttleCPU,
                    tipTitle: "Thermal Posture: Throttle CPU",
                    tipDesc: "Acoustic Priority: Engages Low Power Mode to contain heat while preserving silence."
                )
            }
            .padding(2)
            .background(Design.Color.background.opacity(0.8), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

            // Ceiling slider (if not off)
            if fanVM.safetyPolicy != .off {
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(fanVM.safetyPolicy == .throttleCPU ? "Throttle Threshold" : "Emergency Boost Threshold")
                            .font(Design.Typography.xs)
                            .foregroundStyle(Design.Color.secondaryText)
                        Spacer()
                        Text("\(Int(fanVM.thermalCeilingTemp))°C")
                            .font(Design.Typography.xsMono)
                            .bold()
                            .foregroundStyle(Design.Color.foreground)
                    }

                    Slider(
                        value: Binding(
                            get: { fanVM.thermalCeilingTemp },
                            set: { fanVM.setThermalCeilingTemp($0) }
                        ),
                        in: 70...100,
                        step: 5
                    )
                    .disabled(!host.helperInstalled)
                    .kjolTooltip(
                        title: "Threshold Temperature",
                        description: "Temperature at which the selected thermal posture policy engages (\(Int(fanVM.thermalCeilingTemp))°C)."
                    )

                    Text(fanVM.safetyPolicy.summary)
                        .font(.system(size: 8.5))
                        .foregroundStyle(Design.Color.tertiaryText)
                }
                .padding(6)
                .background(Design.Color.background.opacity(0.4), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func safetyPolicyPill(_ policy: ThermalSafetyPolicy, tipTitle: String, tipDesc: String) -> some View {
        let isSelected = fanVM.safetyPolicy == policy
        return Button(action: {
            withAnimation(.easeInOut(duration: 0.15)) {
                fanVM.setThermalSafetyPolicy(policy)
            }
        }) {
            HStack(spacing: 3) {
                Image(systemName: policy.icon)
                    .font(.system(size: 8.5))
                Text(policy.title)
                    .font(.system(size: 9, weight: isSelected ? .semibold : .regular))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background(
                isSelected ? Design.Color.accent.opacity(0.2) : SwiftUI.Color.clear,
                in: RoundedRectangle(cornerRadius: 4, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(isSelected ? Design.Color.accent.opacity(0.7) : SwiftUI.Color.clear, lineWidth: 1)
            )
            .foregroundStyle(isSelected ? Design.Color.accent : Design.Color.secondaryText)
        }
        .buttonStyle(.plain)
        .disabled(host.busy)
        .kjolTooltip(title: tipTitle, description: tipDesc, placement: .top)
    }

    private func fanProfileSegment(_ profile: FanProfile) -> some View {
        let selected = fanVM.profile == profile
        let (tipTitle, tipDesc): (String, String) = {
            switch profile {
            case .auto:
                return ("Auto Fan Profile", "Delegates fan speed regulation to native macOS AppleSMC firmware.")
            case .adaptive:
                return ("Adaptive Fan Profile", "Dynamic temperature curve with predictive thermal acceleration.")
            case .manual:
                return ("Manual Fan Profile", "Locks fans to a fixed user-selected percentage speed.")
            case .blast:
                return ("Blast Fan Profile", "Forces 100% maximum RPM on all cooling fans.")
            }
        }()

        return Button(action: {
            withAnimation(.easeInOut(duration: 0.15)) {
                fanVM.selectProfile(profile)
            }
        }) {
            VStack(spacing: 2) {
                Image(systemName: profile.icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(profile.title)
                    .font(.system(size: 10, weight: selected ? .semibold : .regular))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(
                selected ? Design.Color.accent.opacity(0.2) : SwiftUI.Color.clear,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(selected ? Design.Color.accent.opacity(0.8) : SwiftUI.Color.clear, lineWidth: 1)
            )
            .foregroundStyle(selected ? Design.Color.accent : Design.Color.secondaryText)
        }
        .buttonStyle(.plain)
        .disabled(host.busy)
        .kjolTooltip(title: tipTitle, description: tipDesc, placement: .top)
    }

    private func adaptiveSubProfilePill(_ sub: AdaptiveSubProfile) -> some View {
        let selected = fanVM.adaptiveSubProfile == sub
        let (tipTitle, tipDesc): (String, String) = {
            switch sub {
            case .gentle:
                return ("Cool Native Curve", "Whisper-quiet curve following macOS acoustics with +15% cooler baseline.")
            case .aggressive:
                return ("Heavy Compute Curve", "Proactive ΔT/Δt thermal acceleration with 12s peak-hold.")
            case .custom:
                return ("Custom Curve", "Interactive 4-milestone spline curve tailored to your preferences.")
            }
        }()

        return Button(action: {
            withAnimation(.easeInOut(duration: 0.15)) {
                fanVM.selectAdaptiveSubProfile(sub)
            }
        }) {
            HStack(spacing: 4) {
                Image(systemName: sub.icon)
                    .font(.system(size: 9, weight: .semibold))
                Text(sub.title)
                    .font(.system(size: 10, weight: selected ? .semibold : .regular))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background(
                selected ? Design.Color.accent.opacity(0.22) : SwiftUI.Color.clear,
                in: RoundedRectangle(cornerRadius: 5, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(selected ? Design.Color.accent.opacity(0.7) : SwiftUI.Color.clear, lineWidth: 1)
            )
            .foregroundStyle(selected ? Design.Color.accent : Design.Color.secondaryText)
        }
        .buttonStyle(.plain)
        .disabled(host.busy)
        .kjolTooltip(title: tipTitle, description: tipDesc, placement: .top)
    }

    private func adaptivePresetCard(_ sub: AdaptiveSubProfile) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: sub == .gentle ? "leaf.fill" : "bolt.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Design.Color.accent)
                Text(sub == .gentle ? "Cool Native Curve" : "Heavy Compute Acceleration")
                    .font(Design.Typography.xs)
                    .bold()
                    .foregroundStyle(Design.Color.foreground)
                Spacer()
                if let t = effectiveTemp {
                    Text("\(Int(t))°C")
                        .font(Design.Typography.xsMono)
                        .foregroundStyle(Design.Color.tertiaryText)
                }
            }

            Text(sub == .gentle
                 ? "Gentle progressive curve following macOS acoustics with +15% cooler baseline and low-pass 20s smoothing."
                 : "Proactive ΔT/Δt thermal acceleration with 12s peak-hold for compilation, rendering, and sustained workloads.")
                .font(.system(size: 9.5))
                .foregroundStyle(Design.Color.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            // Milestone preview dots
            HStack(spacing: 6) {
                if sub == .gentle {
                    presetMilestoneBadge(temp: "45°", rpm: "18%")
                    presetMilestoneBadge(temp: "60°", rpm: "30%")
                    presetMilestoneBadge(temp: "75°", rpm: "55%")
                    presetMilestoneBadge(temp: "90°", rpm: "90%")
                } else {
                    presetMilestoneBadge(temp: "40°", rpm: "15%")
                    presetMilestoneBadge(temp: "55°", rpm: "35%")
                    presetMilestoneBadge(temp: "70°", rpm: "70%")
                    presetMilestoneBadge(temp: "85°", rpm: "100%")
                }
            }
            .padding(.top, 2)
        }
        .padding(8)
        .background(Design.Color.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(SwiftUI.Color.primary.opacity(0.05), lineWidth: 1)
        )
    }

    private func presetMilestoneBadge(temp: String, rpm: String) -> some View {
        HStack(spacing: 2) {
            Text(temp)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(Design.Color.secondaryText)
            Text("→")
                .font(.system(size: 8))
                .foregroundStyle(Design.Color.tertiaryText)
            Text(rpm)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(Design.Color.accent)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(Design.Color.background, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    private func quickSnapButton(percent: Double) -> some View {
        let isCurrent = Int(fanVM.customPercent) == Int(percent)
        return Button(action: {
            fanVM.setCustomPercent(percent, immediate: true)
        }) {
            Text("\(Int(percent))%")
                .font(Design.Typography.xsMono)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 3)
                .background(isCurrent ? Design.Color.accent.opacity(0.25) : Design.Color.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(isCurrent ? Design.Color.accent : Design.Color.tertiaryText.opacity(0.2), lineWidth: 1)
                )
                .foregroundStyle(isCurrent ? Design.Color.accent : Design.Color.secondaryText)
        }
        .buttonStyle(.plain)
        .disabled(host.busy)
    }
}

struct CustomCurveCanvasView: View {
    let anchors: [CurveMilestone]
    let currentTemp: Double?

    private let minT: Double = 35.0
    private let maxT: Double = 95.0

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height

            func xPos(_ t: Double) -> CGFloat {
                let clamped = max(minT, min(maxT, t))
                return CGFloat((clamped - minT) / (maxT - minT)) * (w - 24) + 12
            }

            func yPos(_ rpm: Double) -> CGFloat {
                let clamped = max(0.0, min(100.0, rpm))
                return h - 14 - CGFloat(clamped / 100.0) * (h - 24)
            }

            // Horizontal reference lines (25%, 50%, 75%, 100%)
            for pct in [25.0, 50.0, 75.0, 100.0] {
                let y = yPos(pct)
                var gridPath = Path()
                gridPath.move(to: CGPoint(x: 12, y: y))
                gridPath.addLine(to: CGPoint(x: w - 12, y: y))
                context.stroke(
                    gridPath,
                    with: .color(SwiftUI.Color.primary.opacity(0.05)),
                    lineWidth: 1
                )
            }

            let sorted = anchors.sorted { $0.temp < $1.temp }
            guard !sorted.isEmpty else { return }

            var points: [CGPoint] = []
            points.append(CGPoint(x: xPos(minT), y: yPos(sorted.first!.rpmPercent)))
            for a in sorted {
                points.append(CGPoint(x: xPos(a.temp), y: yPos(a.rpmPercent)))
            }
            points.append(CGPoint(x: xPos(maxT), y: yPos(min(100.0, sorted.last!.rpmPercent + 10))))

            // Build smooth Bezier path
            var curvePath = Path()
            curvePath.move(to: points[0])
            for i in 1..<points.count {
                let p0 = points[i - 1]
                let p1 = points[i]
                let midX = (p0.x + p1.x) / 2
                curvePath.addCurve(to: p1, control1: CGPoint(x: midX, y: p0.y), control2: CGPoint(x: midX, y: p1.y))
            }

            // Shaded fill under curve
            var fillPath = curvePath
            fillPath.addLine(to: CGPoint(x: points.last!.x, y: h - 6))
            fillPath.addLine(to: CGPoint(x: points.first!.x, y: h - 6))
            fillPath.closeSubpath()

            let gradient = Gradient(colors: [
                Design.Color.accent.opacity(0.32),
                Design.Color.accent.opacity(0.02)
            ])
            context.fill(fillPath, with: .linearGradient(gradient, startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: h)))

            // Curve stroke
            context.stroke(
                curvePath,
                with: .color(Design.Color.accent),
                lineWidth: 2.2
            )

            // Milestone anchor dots & guidelines
            for a in sorted {
                let pt = CGPoint(x: xPos(a.temp), y: yPos(a.rpmPercent))

                var vGuide = Path()
                vGuide.move(to: CGPoint(x: pt.x, y: pt.y))
                vGuide.addLine(to: CGPoint(x: pt.x, y: h - 6))
                context.stroke(
                    vGuide,
                    with: .color(SwiftUI.Color.primary.opacity(0.12)),
                    style: StrokeStyle(lineWidth: 1, dash: [2, 2])
                )

                let dotOuter = Path(ellipseIn: CGRect(x: pt.x - 4.5, y: pt.y - 4.5, width: 9, height: 9))
                context.fill(dotOuter, with: .color(Design.Color.accent))

                let dotInner = Path(ellipseIn: CGRect(x: pt.x - 2, y: pt.y - 2, width: 4, height: 4))
                context.fill(dotInner, with: .color(SwiftUI.Color.white))
            }

            // Real-time SoC temperature tracking beacon
            if let curT = currentTemp, curT >= minT && curT <= maxT {
                let curX = xPos(curT)

                var curRpm: Double = sorted.first!.rpmPercent
                if curT <= sorted.first!.temp {
                    curRpm = sorted.first!.rpmPercent
                } else if curT >= sorted.last!.temp {
                    curRpm = sorted.last!.rpmPercent
                } else {
                    for i in 0..<(sorted.count - 1) {
                        let a0 = sorted[i]
                        let a1 = sorted[i + 1]
                        if curT >= a0.temp && curT <= a1.temp {
                            let frac = (curT - a0.temp) / (a1.temp - a0.temp)
                            curRpm = a0.rpmPercent + frac * (a1.rpmPercent - a0.rpmPercent)
                            break
                        }
                    }
                }
                let curY = yPos(curRpm)

                var line = Path()
                line.move(to: CGPoint(x: curX, y: 2))
                line.addLine(to: CGPoint(x: curX, y: h - 6))
                context.stroke(
                    line,
                    with: .color(SwiftUI.Color.cyan.opacity(0.8)),
                    style: StrokeStyle(lineWidth: 1.5, dash: [3, 2])
                )

                let beacon = Path(ellipseIn: CGRect(x: curX - 6, y: curY - 6, width: 12, height: 12))
                context.fill(beacon, with: .color(SwiftUI.Color.cyan.opacity(0.35)))
                let beaconCore = Path(ellipseIn: CGRect(x: curX - 3, y: curY - 3, width: 6, height: 6))
                context.fill(beaconCore, with: .color(SwiftUI.Color.cyan))
            }
        }
        .frame(height: 85)
        .background(Design.Color.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(SwiftUI.Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

struct CustomCurveEditorView: View {
    @ObservedObject var fanVM: FanControlViewModel
    let currentTemp: Double?
    let disabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Live spline curve visualization
            CustomCurveCanvasView(
                anchors: fanVM.customCurveAnchors,
                currentTemp: currentTemp
            )

            // Temperature Axis Legend
            HStack {
                Text("35°C (Idle)")
                    .font(.system(size: 8.5, design: .monospaced))
                    .foregroundStyle(Design.Color.tertiaryText)
                Spacer()
                if let t = currentTemp {
                    HStack(spacing: 3) {
                        Circle()
                            .fill(SwiftUI.Color.cyan)
                            .frame(width: 5, height: 5)
                        Text("\(Int(t))°C Live")
                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(SwiftUI.Color.cyan)
                    }
                }
                Spacer()
                Text("95°C (Max)")
                    .font(.system(size: 8.5, design: .monospaced))
                    .foregroundStyle(Design.Color.tertiaryText)
            }
            .padding(.horizontal, 4)

            // 4 Milestone Target Sliders
            VStack(spacing: 3) {
                ForEach(fanVM.customCurveAnchors) { anchor in
                    milestoneSliderRow(anchor)
                }
            }

            // Quick reset button
            HStack {
                Spacer()
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        fanVM.resetCurveToRecommended()
                    }
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 9))
                        Text("Reset to Defaults")
                            .font(.system(size: 9))
                    }
                    .foregroundStyle(Design.Color.secondaryText)
                }
                .buttonStyle(.plain)
                .disabled(disabled)
                .kjolTooltip(title: "Reset Curve", description: "Reverts custom thermal curve milestone anchors back to recommended defaults.")
            }
            .padding(.top, 2)
        }
    }

    private func milestoneSliderRow(_ anchor: CurveMilestone) -> some View {
        let liveRPM = fanVM.anchorRPM(for: anchor.temp)
        return HStack(spacing: 6) {
            // Milestone label & temp badge
            HStack(spacing: 3) {
                Text("\(Int(anchor.temp))°C")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Design.Color.foreground)
                Text("(\(anchor.label))")
                    .font(.system(size: 9))
                    .foregroundStyle(Design.Color.secondaryText)
            }
            .frame(width: 80, alignment: .leading)

            Slider(
                value: fanVM.anchorBinding(for: anchor.temp),
                in: 0...100,
                step: 5,
                onEditingChanged: { editing in
                    if !editing {
                        fanVM.commitCurveAnchor(temp: anchor.temp)
                    }
                }
            )
            .disabled(disabled)
            .kjolTooltip(
                title: "\(anchor.label) Anchor (\(Int(anchor.temp))°C)",
                description: "Target fan speed of \(Int(liveRPM))% when junction temperature reaches \(Int(anchor.temp))°C."
            )

            Text("\(Int(liveRPM))%")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(Design.Color.accent)
                .frame(width: 32, alignment: .trailing)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Design.Color.background.opacity(0.4), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

struct PowerBatteryCardView: View {
    @ObservedObject var powerVM: PowerViewModel
    @ObservedObject var telemetryVM: TelemetryViewModel
    @ObservedObject var host: Host
    @State private var showAdvanced: Bool = false
    @State private var showLegacyControls: Bool = false

    var body: some View {
        CardContainer(title: "Power & Battery Management", backgroundResource: "battery-header.jpg") {
            VStack(alignment: .leading, spacing: Design.Spacing.space2) {
                // Battery Section Branch based on BatteryControlTier
                switch powerVM.batteryTier {
                case .desktopNoBattery:
                    desktopPowerSection
                case .systemManaged:
                    systemManagedBatterySection
                case .directSMC:
                    directSmcBatterySection
                }
            }
        }
    }

    // MARK: - Subsections

    private var desktopPowerSection: some View {
        HStack(spacing: 8) {
            Image(systemName: "powerplug.fill")
                .font(Design.Typography.sm)
                .foregroundStyle(Design.Color.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text("Direct AC Power")
                    .font(Design.Typography.xs)
                    .bold()
                    .foregroundStyle(Design.Color.foreground)
                Text("Stationary Apple Silicon hardware without internal battery.")
                    .font(.system(size: 10))
                    .foregroundStyle(Design.Color.tertiaryText)
            }
            Spacer()
        }
        .padding(Design.Spacing.space2)
        .background(Design.Color.background, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .kjolTooltip(title: "Stationary Desktop Hardware", description: "Direct wall power connected. Battery management and charge throttling are omitted.")
    }

    private var systemManagedBatterySection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.space2) {
            // Live Battery Telemetry Grid
            HStack(spacing: Design.Spacing.space2) {
                batteryMetricBadge(
                    icon: telemetryVM.isCharging ? "bolt.fill" : (telemetryVM.externalConnected ? "powerplug.fill" : "battery.100"),
                    label: "Charge",
                    value: "\(telemetryVM.batteryCharge)%",
                    color: telemetryVM.isCharging ? Design.Color.accent : Design.Color.foreground,
                    tipTitle: "Battery Charge Level",
                    tipDesc: "Current State of Charge (SoC) as reported by system power source."
                )
                batteryMetricBadge(
                    icon: "heart.fill",
                    label: "Health",
                    value: telemetryVM.batteryHealthPercent != nil ? String(format: "%.0f%%", telemetryVM.batteryHealthPercent!) : "Normal",
                    color: Design.Color.accent,
                    tipTitle: "Battery Health",
                    tipDesc: "Maximum capacity relative to when it was brand new."
                )
                batteryMetricBadge(
                    icon: "arrow.triangle.2.circlepath",
                    label: "Cycles",
                    value: telemetryVM.batteryCycles > 0 ? "\(telemetryVM.batteryCycles)" : "—",
                    color: Design.Color.secondaryText,
                    tipTitle: "Cycle Count",
                    tipDesc: "Total number of complete 100% discharge cycles accumulated by the cell."
                )
                batteryMetricBadge(
                    icon: "thermometer.medium",
                    label: "Temp",
                    value: telemetryVM.batteryTemp != nil ? "\(Int(telemetryVM.batteryTemp!))°C" : "—",
                    color: Design.Color.secondaryText,
                    tipTitle: "Battery Temperature",
                    tipDesc: "Internal battery temperature sensor measurement."
                )
            }

            // Clean Native Management Guidance & Settings Action
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Design.Color.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Native macOS Battery Management")
                            .font(Design.Typography.xs)
                            .bold()
                            .foregroundStyle(Design.Color.foreground)
                        Text("Set charging limits in macOS system settings - 80% charge limit recommended for battery health")
                            .font(.system(size: 10))
                            .foregroundStyle(Design.Color.tertiaryText)
                    }
                    Spacer()
                }

                Button(action: {
                    BatterySettingsLauncher.openSettings()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "gearshape")
                            .font(Design.Typography.xs)
                        Text("Open macOS Battery Settings")
                            .font(Design.Typography.xs)
                            .bold()
                        Spacer()
                        Image(systemName: "arrow.up.forward.app")
                            .font(.system(size: 10))
                            .foregroundStyle(Design.Color.tertiaryText)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Design.Color.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Design.Color.accent.opacity(0.3), lineWidth: 1)
                    )
                    .foregroundStyle(Design.Color.accent)
                }
                .buttonStyle(.plain)
                .kjolTooltip(
                    title: "Open Battery Settings",
                    description: "Navigates directly to the macOS System Settings pane to configure native 80% limit."
                )
            }
            .padding(Design.Spacing.space2)
            .background(Design.Color.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            // Optional Legacy Hardware Controls Drawer (Cleanly Collapsed by Default)
            ExpandableSectionHeader(
                title: "Legacy SMC Hardware Controls",
                icon: "lock.shield",
                isExpanded: showLegacyControls
            ) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showLegacyControls.toggle()
                }
            }

            if showLegacyControls {
                VStack(alignment: .leading, spacing: Design.Spacing.space2) {
                    Text("Direct SMC register writes are gated by macOS 27 integrity protection. Displayed for diagnostics only.")
                        .font(.system(size: 10))
                        .foregroundStyle(Design.Color.warning)
                        .padding(.bottom, 2)

                    directSmcControlsView(disabled: true)
                }
                .padding(.top, 2)
            }
        }
    }

    private var directSmcBatterySection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.space2) {
            directSmcControlsView(disabled: false)
        }
    }

    private func batteryMetricBadge(icon: String, label: String, value: String, color: SwiftUI.Color, tipTitle: String, tipDesc: String) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                    .foregroundStyle(color)
                Text(label)
                    .font(.system(size: 9))
                    .foregroundStyle(Design.Color.tertiaryText)
            }
            Text(value)
                .font(Design.Typography.xsMono)
                .bold()
                .foregroundStyle(Design.Color.foreground)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .background(Design.Color.background, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .contentShape(Rectangle())
        .kjolTooltip(title: tipTitle, description: tipDesc)
    }

    private func directSmcControlsView(disabled: Bool) -> some View {
        VStack(alignment: .leading, spacing: Design.Spacing.space2) {
            // Main Charge Limit Control
            VStack(alignment: .leading, spacing: Design.Spacing.space1) {
                HStack {
                    Text("Charge Limit Target")
                        .font(Design.Typography.xs)
                        .foregroundStyle(Design.Color.secondaryText)
                    Spacer()
                    Text("\(powerVM.chargeLimit)%")
                        .font(Design.Typography.xsMono)
                        .bold()
                        .foregroundStyle(powerVM.limitEnabled && !disabled ? Design.Color.foreground : Design.Color.tertiaryText)
                    Text(disabled ? "(Restricted)" : (powerVM.limitEnabled ? "(Active)" : "(Disabled)"))
                        .font(Design.Typography.xs)
                        .foregroundStyle(powerVM.limitEnabled && !disabled ? Design.Color.accent : Design.Color.tertiaryText)
                }

                HStack(spacing: Design.Spacing.space2) {
                    Slider(
                        value: Binding(
                            get: { Double(powerVM.chargeLimit) },
                            set: { powerVM.setChargeLimit(Int($0), enabled: true) }
                        ),
                        in: 50...90,
                        step: 5
                    )
                    .disabled(!powerVM.limitEnabled || disabled || host.busy)
                    .opacity(powerVM.limitEnabled && !disabled ? 1.0 : 0.4)
                    .kjolTooltip(
                        title: "Charge Limit Slider",
                        description: "Select target maximum battery charge limit percentage between 50% and 90%."
                    )
                }
                .frame(height: 20)

                if powerVM.limitEnabled && !disabled {
                    Text("Sailing Range: \(max(1, powerVM.chargeLimit - powerVM.sailingDiff))% – \(powerVM.chargeLimit)%")
                        .font(Design.Typography.xsMono)
                        .foregroundStyle(Design.Color.tertiaryText)
                }
            }

            // Quick Action Buttons: Top Up (100%) & Discharge on AC
            HStack(spacing: Design.Spacing.space2) {
                Button(action: {
                    powerVM.toggleTopUp(!powerVM.topUpActive)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: powerVM.topUpActive ? "bolt.fill" : "bolt")
                        Text("Top Up (100%)")
                            .font(Design.Typography.xs)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(powerVM.topUpActive ? Design.Color.accent.opacity(0.2) : Design.Color.background, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(powerVM.topUpActive ? Design.Color.accent : Design.Color.tertiaryText.opacity(0.3), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(disabled || host.busy)
                .opacity(!disabled ? 1.0 : 0.4)
                .kjolTooltip(
                    title: "Top Up (100%)",
                    description: "Temporarily disables charge ceiling to fully charge battery for travel."
                )

                Button(action: {
                    powerVM.toggleDischarge(!powerVM.dischargeActive)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: powerVM.dischargeActive ? "arrow.down.circle.fill" : "arrow.down.circle")
                        Text("Discharge to Limit")
                            .font(Design.Typography.xs)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(powerVM.dischargeActive ? Design.Color.warning.opacity(0.2) : Design.Color.background, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(powerVM.dischargeActive ? Design.Color.warning : Design.Color.tertiaryText.opacity(0.3), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(disabled || host.busy)
                .opacity(!disabled ? 1.0 : 0.4)
                .kjolTooltip(
                    title: "Discharge to Limit",
                    description: "Draws battery power down to the target limit while still connected to AC power."
                )
            }

            Divider()

            ExpandableSectionHeader(
                title: "Advanced Battery Controls",
                icon: "slider.horizontal.3",
                isExpanded: showAdvanced
            ) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showAdvanced.toggle()
                }
            }

            if showAdvanced {
                VStack(alignment: .leading, spacing: Design.Spacing.space2) {
                    // Battery Cycle Count
                    HStack {
                        Text("Battery Cycle Count")
                            .font(Design.Typography.xs)
                            .foregroundStyle(Design.Color.secondaryText)
                        Spacer()
                        Text(telemetryVM.batteryCycles > 0 ? "\(telemetryVM.batteryCycles)" : "—")
                            .font(Design.Typography.xsMono)
                            .bold()
                            .foregroundStyle(Design.Color.foreground)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Design.Color.background, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .kjolTooltip(title: "Hardware Cycle Count", description: "Direct SMC register readout of full charge discharge cycles.")

                    // Sailing Gap Slider
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("Sailing Gap (Hysteresis)")
                                .font(Design.Typography.xs)
                                .foregroundStyle(Design.Color.secondaryText)
                            Spacer()
                            Text("±\(powerVM.sailingDiff)%")
                                .font(Design.Typography.xsMono)
                                .foregroundStyle(Design.Color.tertiaryText)
                        }
                        Slider(
                            value: Binding(
                                get: { Double(powerVM.sailingDiff) },
                                set: { powerVM.setSailingDiff(Int($0)) }
                            ),
                            in: 2...10,
                            step: 1
                        )
                        .controlSize(.small)
                        .disabled(disabled || host.busy)
                        .kjolTooltip(
                            title: "Sailing Gap Hysteresis",
                            description: "Charge buffer to prevent repetitive micro-charging cycles around the charge ceiling."
                        )
                    }

                    // Overheat Protection
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Toggle("Heat Protection", isOn: Binding(
                                get: { powerVM.heatProtectionEnabled },
                                set: { powerVM.setHeatProtection(enabled: $0, maxTemp: powerVM.maxTempC) }
                            ))
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .disabled(disabled || host.busy)
                            .kjolTooltip(
                                title: "Thermal Charging Inhibit",
                                description: "Pauses charging automatically if battery cells exceed the specified thermal ceiling."
                            )

                            Spacer()

                            Text("\(Int(powerVM.maxTempC))°C")
                                .font(Design.Typography.xsMono)
                                .foregroundStyle(powerVM.heatProtectionEnabled && !disabled ? Design.Color.secondaryText : Design.Color.tertiaryText)
                        }

                        if powerVM.heatProtectionEnabled {
                            Slider(
                                value: Binding(
                                    get: { powerVM.maxTempC },
                                    set: { powerVM.setHeatProtection(enabled: true, maxTemp: $0) }
                                ),
                                in: 30...45,
                                step: 1
                            )
                            .controlSize(.small)
                            .disabled(disabled || host.busy)
                            .kjolTooltip(
                                title: "Battery Thermal Cutoff",
                                description: "Maximum allowable cell temperature during charging (\(Int(powerVM.maxTempC))°C)."
                            )
                        }
                    }

                    // Battery Calibration Mode
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Battery Calibration")
                                .font(Design.Typography.xs)
                                .foregroundStyle(Design.Color.secondaryText)
                            Spacer()
                            if powerVM.calibrationState != "idle" && powerVM.calibrationState != "completed" {
                                Button("Cancel") {
                                    powerVM.triggerCalibration(action: "stop")
                                }
                                .buttonStyle(.plain)
                                .font(Design.Typography.xs)
                                .foregroundStyle(Design.Color.warning)
                                .kjolTooltip(title: "Cancel Calibration", description: "Aborts the multi-phase battery conditioning cycle.")
                            } else {
                                Button("Start Cycle") {
                                    powerVM.triggerCalibration(action: "start")
                                }
                                .buttonStyle(.plain)
                                .font(Design.Typography.xs)
                                .foregroundStyle(Design.Color.accent)
                                .disabled(disabled || host.busy)
                                .kjolTooltip(
                                    title: "Start Conditioning Cycle",
                                    description: "Runs a 4-phase cycle (100% soak → 15% discharge → recharge) to recalibrate gas-gauge accuracy."
                                )
                            }
                        }

                        if powerVM.calibrationState != "idle" && powerVM.calibrationState != "completed" {
                            VStack(alignment: .leading, spacing: 4) {
                                ProgressView(value: powerVM.calibrationProgress, total: 1.0)
                                    .controlSize(.small)
                                HStack {
                                    Text(powerVM.calibrationMessage)
                                        .font(Design.Typography.xsMono)
                                        .foregroundStyle(Design.Color.tertiaryText)
                                    Spacer()
                                    Text("\(Int(powerVM.calibrationProgress * 100))%")
                                        .font(Design.Typography.xsMono)
                                        .foregroundStyle(Design.Color.secondaryText)
                                }
                            }
                        } else if let lastCal = powerVM.lastCalibration {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.seal.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Design.Color.accent)
                                    Text("Last calibrated: \(lastCal.relativeTime)")
                                        .font(Design.Typography.xs)
                                        .foregroundStyle(Design.Color.foreground)
                                }
                                HStack(spacing: 4) {
                                    Text("Health: \(String(format: "%.1f%%", lastCal.healthPercent))")
                                        .font(Design.Typography.xsMono)
                                        .foregroundStyle(Design.Color.secondaryText)
                                    if lastCal.rawMaxCapacity > 0 && lastCal.designCapacity > 0 {
                                        Text("(\(lastCal.rawMaxCapacity)/\(lastCal.designCapacity) mAh)")
                                            .font(Design.Typography.xsMono)
                                            .foregroundStyle(Design.Color.tertiaryText)
                                    }
                                    if lastCal.cycleCount > 0 {
                                        Text("• \(lastCal.cycleCount) cycles")
                                            .font(Design.Typography.xsMono)
                                            .foregroundStyle(Design.Color.tertiaryText)
                                    }
                                }
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(Design.Color.background, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        } else {
                            Text("4-phase cycle: 100% soak → 15% AC discharge → target recharge")
                                .font(Design.Typography.xsMono)
                                .foregroundStyle(Design.Color.tertiaryText)
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
    }
}

struct UpdateBannerView: View {
    @ObservedObject var updateVM: UpdateViewModel

    var body: some View {
        switch updateVM.state {
        case .available(let info):
            HStack(spacing: Design.Spacing.space2) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Update Available: v\(info.version)")
                        .font(Design.Typography.xs)
                        .bold()
                        .foregroundStyle(Design.Color.accent)
                    Text("Click to download & install")
                        .font(Design.Typography.xs)
                        .foregroundStyle(Design.Color.secondaryText)
                }
                Spacer()
                Button("Update Now") {
                    updateVM.startDownload(for: info)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .kjolTooltip(title: "Download Update", description: "Downloads release v\(info.version) installer from GitHub.")
            }
            .padding(Design.Spacing.space2)
            .background(Design.Color.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

        case .downloading(let progress):
            HStack(spacing: Design.Spacing.space2) {
                Text("Downloading Update...")
                    .font(Design.Typography.xs)
                    .foregroundStyle(Design.Color.secondaryText)
                Spacer()
                ProgressView(value: progress)
                    .frame(width: 80)
                Text("\(Int(progress * 100))%")
                    .font(Design.Typography.xsMono)
                    .foregroundStyle(Design.Color.secondaryText)
            }
            .padding(Design.Spacing.space2)
            .background(Design.Color.cardBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

        case .readyToInstall(let url):
            HStack(spacing: Design.Spacing.space2) {
                Text("Update Ready")
                    .font(Design.Typography.xs)
                    .bold()
                Spacer()
                Button("Launch Installer") {
                    updateVM.installUpdate(localURL: url)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .kjolTooltip(title: "Install Update", description: "Opens the downloaded .pkg installer to upgrade Kjol.")
            }
            .padding(Design.Spacing.space2)
            .background(Design.Color.accent.opacity(0.15), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

        default:
            EmptyView()
        }
    }
}

struct FooterView: View {
    @ObservedObject var host: Host
    @ObservedObject var updateVM: UpdateViewModel

    var body: some View {
        VStack(spacing: Design.Spacing.space1) {
            if let err = host.errorMessage, !err.isEmpty {
                Text(err)
                    .font(Design.Typography.xs)
                    .foregroundStyle(Design.Color.warning)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(2)
            }
            HStack {
                Button("Quit Kjol", action: kjolQuit)
                    .buttonStyle(.plain)
                    .font(Design.Typography.xs)
                    .foregroundStyle(Design.Color.secondaryText)
                    .kjolTooltip(title: "Quit Kjol", description: "Terminates the Kjol application and deactivates always-on if active.")

                Spacer(minLength: 0)

                switch updateVM.state {
                case .checking:
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.small)
                        Text("Checking...")
                            .font(Design.Typography.xs)
                            .foregroundStyle(Design.Color.tertiaryText)
                    }
                case .upToDate:
                    Button {
                        updateVM.checkForUpdates(silent: false)
                    } label: {
                        HStack(spacing: 3) {
                            Text("Up to Date (v\(currentVersion))")
                                .font(Design.Typography.xsMono)
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 8, weight: .bold))
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Design.Color.tertiaryText)
                    .kjolTooltip(title: "Check for Updates", description: "Kjol v\(currentVersion) is up to date. Click to re-check for new releases.")
                case .error:
                    Button("Check Failed: Retry") {
                        updateVM.checkForUpdates(silent: false)
                    }
                    .buttonStyle(.plain)
                    .font(Design.Typography.xs)
                    .foregroundStyle(Design.Color.warning)
                    .kjolTooltip(title: "Retry Update Check", description: "Reconnects to GitHub Releases API to verify updates.")
                default:
                    Button("Check for Updates") {
                        updateVM.checkForUpdates(silent: false)
                    }
                    .buttonStyle(.plain)
                    .font(Design.Typography.xs)
                    .foregroundStyle(Design.Color.secondaryText)
                    .kjolTooltip(title: "Check for Updates", description: "Queries GitHub Releases to check for newer versions of Kjol.")
                }
            }
        }
        .frame(minHeight: 20)
    }

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
}

struct KjolView: View {
    @EnvironmentObject var host: Host
    @StateObject private var tooltipCoordinator = TooltipCoordinator()

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: Design.Spacing.space3) {
                HeaderView(host: host)
                QuickActionsBarView(powerVM: host.powerVM, host: host)
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: Design.Spacing.space3) {
                        TelemetryCardView(telemetryVM: host.telemetryVM)
                        if !host.helperInstalled {
                            HelperMissingCardView(host: host)
                        } else {
                            FanControlCardView(fanVM: host.fanControlVM, telemetryVM: host.telemetryVM, host: host)
                            PowerBatteryCardView(powerVM: host.powerVM, telemetryVM: host.telemetryVM, host: host)
                        }
                        UpdateBannerView(updateVM: host.updateVM)
                    }
                    .padding(.bottom, 2)
                }
                FooterView(host: host, updateVM: host.updateVM)
            }
            .padding(Design.Spacing.space4)

            if let tip = tooltipCoordinator.activeTooltip {
                ActiveTooltipOverlay(tooltip: tip)
                    .allowsHitTesting(false)
                    .zIndex(999999)
            }
        }
        .coordinateSpace(name: "kjolWindowSpace")
        .frame(width: 513, height: 580)
        .background(Design.Color.background)
        .environmentObject(tooltipCoordinator)
    }
}

class KjolHostingController<Content: View>: NSHostingController<Content> {
    override func viewDidLoad() {
        super.viewDidLoad()
        if #available(macOS 13.0, *) {
            sizingOptions = []
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover?
    private let host = Host()
    private var popoverShown = false {
        didSet { updatePolling() }
    }
    private var cancellables = Set<AnyCancellable>()
    private var cachedStatusIcon: NSImage?
    private var memoryPressureSource: DispatchSourceMemoryPressure?

    private func loadStatusItemImage() -> NSImage {
        if let cached = cachedStatusIcon {
            return cached
        }
        if let img = loadBundleNSImage("KjolStatusIcon.png") ?? loadBundleNSImage("KjolStatusIcon") {
            img.size = NSSize(width: 18, height: 18)
            img.isTemplate = true
            cachedStatusIcon = img
            return img
        }
        let fallback = NSImage(systemSymbolName: "bolt", accessibilityDescription: "Kjol") ?? NSImage()
        fallback.isTemplate = true
        cachedStatusIcon = fallback
        return fallback
    }

    private func updateStatusItemIcon() {
        // Keep status item icon strictly uniform in size and template behavior to eliminate menu bar layout shifts.
        statusItem.button?.image = loadStatusItemImage()
        statusItem.button?.contentTintColor = host.powerVM.alwaysOn ? .controlAccentColor : nil
        var tip = "Kjol"
        if let t = host.telemetryVM.socTemp { tip += String(format: " · %.0f°C", t) }
        if !host.telemetryVM.fans.isEmpty {
            let rpms = host.telemetryVM.fans.map { "\(Int($0.actualRPM))" }.joined(separator: "/")
            tip += " · \(rpms) rpm"
        }
        if host.powerVM.alwaysOn { tip += " · Always-On" }
        if let err = host.errorMessage, !err.isEmpty { tip += " · \(err)" }
        statusItem.button?.toolTip = tip
    }

    private func updatePolling() {
        if popoverShown {
            host.refresh()
            host.updateVM.checkForUpdates(silent: true)
            host.startPolling(interval: 5.0)
        } else {
            host.stopPolling()
        }
    }

    private func setupMemoryPressureMonitoring() {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: DispatchQueue.main)
        source.setEventHandler {
            autoreleasepool {
                _ = malloc_zone_pressure_relief(nil, 0)
            }
        }
        source.resume()
        memoryPressureSource = source
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        if #available(macOS 13.0, *) {
            do {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } catch {
                print("Failed to register SMAppService: \(error)")
            }
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let btn = statusItem.button {
            btn.image = loadStatusItemImage()
            btn.action = #selector(togglePopover(_:))
            btn.target = self
        }

        setupMemoryPressureMonitoring()
        updateStatusItemIcon()
        let scheduleIconUpdate: (Any) -> Void = { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateStatusItemIcon()
            }
        }
        host.telemetryVM.objectWillChange
            .sink(receiveValue: scheduleIconUpdate)
            .store(in: &cancellables)
        host.powerVM.objectWillChange
            .sink(receiveValue: scheduleIconUpdate)
            .store(in: &cancellables)
        host.fanControlVM.objectWillChange
            .sink(receiveValue: scheduleIconUpdate)
            .store(in: &cancellables)
        host.$busy
            .sink(receiveValue: scheduleIconUpdate)
            .store(in: &cancellables)
        host.$errorMessage
            .sink(receiveValue: scheduleIconUpdate)
            .store(in: &cancellables)

        updatePolling()
    }

    private func buildPopover() -> NSPopover {
        let p = NSPopover()
        p.behavior = .transient
        p.delegate = self
        p.animates = false
        p.contentSize = CGSize(width: 513, height: 580)
        let controller = KjolHostingController(rootView: KjolView().environmentObject(host))
        controller.preferredContentSize = CGSize(width: 513, height: 580)
        p.contentViewController = controller
        return p
    }

    private func teardownPopover() {
        guard let pop = popover else { return }
        popover = nil
        pop.close()
        pop.contentViewController = nil
        autoreleasepool {
            _ = malloc_zone_pressure_relief(nil, 0)
        }
    }

    @objc func togglePopover(_ sender: Any?) {
        if let pop = popover, pop.isShown {
            pop.performClose(nil)
            popoverShown = false
            teardownPopover()
            return
        }
        let pop = buildPopover()
        popover = pop
        if let btn = statusItem.button {
            pop.show(relativeTo: btn.bounds, of: btn, preferredEdge: .minY)
            if let window = pop.contentViewController?.view.window {
                window.animationBehavior = .none
            }
        }
        popoverShown = true
    }

    func popoverDidClose(_ notification: Notification) {
        popoverShown = false
        teardownPopover()
    }

    func applicationWillTerminate(_ notification: Notification) {
        memoryPressureSource?.cancel()
        memoryPressureSource = nil
        teardownPopover()
        if host.powerVM.alwaysOn {
            host.syncSetAlwaysOn(false)
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
