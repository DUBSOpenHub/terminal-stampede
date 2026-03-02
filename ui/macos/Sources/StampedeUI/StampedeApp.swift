import SwiftUI
import AppKit

@main
struct StampedeUIApp: App {
    @StateObject private var state: StampedeState = {
        let args = ProcessInfo.processInfo.arguments
        let runId = args.first(where: { $0.hasPrefix("run-") }) ?? ""
        let basePath = ProcessInfo.processInfo.environment["STAMPEDE_BASE"]
        let s = StampedeState(basePath: basePath, runId: runId)
        if s.runId.isEmpty {
            return StampedeState.demo()
        }
        return s
    }()

    var body: some Scene {
        WindowGroup("⚡ Terminal Stampede") {
            DashboardView()
                .environmentObject(state)
                .frame(minWidth: 1080, minHeight: 700)
                .background(StampedeColors.bgDeep)
                .onAppear {
                    if state.isRunning || !state.runId.isEmpty {
                        state.startMonitoring()
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandMenu("Agents") {
                Button("Next Agent") {}
                    .keyboardShortcut("]", modifiers: [.command, .option])
                Button("Previous Agent") {}
                    .keyboardShortcut("[", modifiers: [.command, .option])
                Button("Zoom Agent") {}
                    .keyboardShortcut("z", modifiers: [.command, .option])
                Divider()
                Button("Refresh") { state.refresh() }
                    .keyboardShortcut("r")
            }
        }

        MenuBarExtra("Stampede", systemImage: "bolt.fill") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "bolt.fill")
                        .foregroundColor(StampedeColors.gold)
                    Text("Terminal Stampede")
                        .font(.headline)
                }
                Divider()
                if state.isRunning {
                    Text("Active: \(state.activeCount) agents")
                    Text("Done: \(state.doneTasks)/\(state.totalTasks) tasks")
                    Text("Cost: $\(String(format: "%.2f", state.totalCost))")
                } else {
                    Text("No active run")
                        .foregroundStyle(.secondary)
                }
                Divider()
                Button("Open Dashboard") {
                    NSApp.activate(ignoringOtherApps: true)
                }
                Button("Quit") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
            .padding(8)
            .frame(width: 200)
        }

        Settings {
            PreferencesView()
                .environmentObject(state)
        }
    }
}

// MARK: - Dashboard

struct DashboardView: View {
    @EnvironmentObject var state: StampedeState

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                Image(systemName: "bolt.fill")
                    .foregroundColor(StampedeColors.gold)
                    .font(.title2)
                Text("TERMINAL STAMPEDE")
                    .font(.system(.title3, design: .monospaced, weight: .bold))
                    .foregroundColor(StampedeColors.gold)

                Spacer()

                if !state.runId.isEmpty {
                    Text(state.runId)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(StampedeColors.textSecondary)
                }

                Text(state.formattedElapsed)
                    .font(.system(.body, design: .monospaced, weight: .semibold))
                    .foregroundColor(StampedeColors.textPrimary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(StampedeColors.bgSurface)

            // Stats bar
            HStack(spacing: 16) {
                StatPill(label: "Active", value: "\(state.activeCount)", color: StampedeColors.green)
                StatPill(label: "Done", value: "\(state.doneCount)", color: StampedeColors.blue)
                StatPill(label: "Failed", value: "\(state.failedCount)", color: StampedeColors.red)
                Spacer()
                StatPill(label: "Tasks", value: "\(state.doneTasks)/\(state.totalTasks)", color: StampedeColors.gold)
                StatPill(label: "Tokens", value: formatTokens(state.totalTokens), color: StampedeColors.textSecondary)
                StatPill(label: "Cost", value: "$\(String(format: "%.2f", state.totalCost))", color: StampedeColors.gold)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(StampedeColors.bgElevated)

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(StampedeColors.border)
                        .frame(height: 4)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(StampedeColors.gold)
                        .frame(width: geo.size.width * state.overallProgress, height: 4)
                }
            }
            .frame(height: 4)

            // Main content
            NavigationSplitView {
                AgentSidebar()
            } detail: {
                AgentGrid()
            }
        }
    }

    func formatTokens(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.0fK", Double(n) / 1_000) }
        return "\(n)"
    }
}

// MARK: - Components

struct StatPill: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(StampedeColors.textTertiary)
            Text(value)
                .font(.system(.caption, design: .monospaced, weight: .bold))
                .foregroundColor(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(StampedeColors.bgSurface.opacity(0.5))
        .cornerRadius(4)
    }
}

struct AgentSidebar: View {
    @EnvironmentObject var state: StampedeState

    var body: some View {
        List(state.agents) { agent in
            HStack(spacing: 8) {
                Image(systemName: agent.status.sfSymbol)
                    .foregroundColor(agent.status.color)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 2) {
                    Text(agent.name)
                        .font(.system(.body, design: .monospaced, weight: .semibold))
                        .foregroundColor(StampedeColors.textPrimary)
                    Text(agent.model)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(StampedeColors.textTertiary)
                }

                Spacer()

                Text(agent.status.label)
                    .font(.system(.caption2, design: .monospaced, weight: .bold))
                    .foregroundColor(agent.status.color)
            }
            .padding(.vertical, 4)
            .listRowBackground(StampedeColors.bgSurface)
        }
        .navigationTitle("Agents")
        .scrollContentBackground(.hidden)
        .background(StampedeColors.bgDeep)
    }
}

struct AgentGrid: View {
    @EnvironmentObject var state: StampedeState

    let columns = [
        GridItem(.adaptive(minimum: 280, maximum: 400), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            // Conflict warnings
            if !state.conflicts.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(state.conflicts) { conflict in
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(conflict.severity.color)
                            Text(conflict.filePath)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(StampedeColors.textPrimary)
                            Text("(\(conflict.agentIds.joined(separator: " vs ")))")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(StampedeColors.textSecondary)
                        }
                    }
                }
                .padding(12)
                .background(StampedeColors.orange.opacity(0.1))
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(StampedeColors.orange.opacity(0.3)))
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(state.agents) { agent in
                    AgentCard(agent: agent)
                }
            }
            .padding(16)
        }
        .background(StampedeColors.bgDeep)
    }
}

struct AgentCard: View {
    let agent: Agent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: agent.status.sfSymbol)
                    .foregroundColor(agent.status.color)
                Text(agent.name.uppercased())
                    .font(.system(.caption, design: .monospaced, weight: .bold))
                    .foregroundColor(StampedeColors.textPrimary)
                Spacer()
                Text(agent.status.label)
                    .font(.system(.caption2, design: .monospaced, weight: .bold))
                    .foregroundColor(agent.status.color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(agent.status.color.opacity(0.15))
                    .cornerRadius(4)
            }

            // Task
            if !agent.task.isEmpty {
                Text(agent.task)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(StampedeColors.textSecondary)
                    .lineLimit(1)
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(StampedeColors.border)
                        .frame(height: 3)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(agent.status.color)
                        .frame(width: geo.size.width * agent.progress, height: 3)
                }
            }
            .frame(height: 3)

            // Stats
            HStack {
                Label(agent.formattedTokens, systemImage: "text.word.spacing")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(StampedeColors.textTertiary)
                Spacer()
                Label(agent.formattedTime, systemImage: "clock")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(StampedeColors.textTertiary)
                Spacer()
                Text("$\(String(format: "%.2f", agent.estimatedCost))")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(StampedeColors.gold)
            }

            // Activity
            Text(agent.activity)
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(StampedeColors.gold.opacity(0.8))
                .lineLimit(1)
        }
        .padding(12)
        .stampedeCard()
        .goldGlow()
    }
}

// MARK: - Preferences

struct PreferencesView: View {
    @EnvironmentObject var state: StampedeState
    @AppStorage("themeMode") private var themeMode = "System"
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @AppStorage("maxPanes") private var maxPanes = 8

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $themeMode) {
                    Text("System").tag("System")
                    Text("Dark").tag("Dark")
                    Text("Light").tag("Light")
                }
            }
            Section("Stampede") {
                TextField("Run ID", text: $state.runId)
                Stepper("Max panes: \(maxPanes)", value: $maxPanes, in: 1...20)
                Button("Refresh") { state.refresh() }
                    .keyboardShortcut("r")
            }
            Section("Notifications") {
                Toggle("Enable notifications", isOn: $notificationsEnabled)
            }
        }
        .padding(20)
        .frame(width: 420, height: 300)
    }
}
