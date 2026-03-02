import Foundation
import Combine
import SwiftUI

@MainActor
class StampedeState: ObservableObject {
    @Published var agents: [Agent] = []
    @Published var conflicts: [FileConflict] = []
    @Published var totalTasks: Int = 0
    @Published var doneTasks: Int = 0
    @Published var isRunning: Bool = false
    @Published var startTime: Date?
    @Published var runId: String

    private var timer: Timer?
    private let basePath: String

    var overallProgress: Double {
        guard totalTasks > 0 else { return 0 }
        return Double(doneTasks) / Double(totalTasks)
    }
    var totalTokens: Int { agents.reduce(0) { $0 + $1.tokensUsed } }
    var totalCost: Double { agents.reduce(0) { $0 + $1.estimatedCost } }
    var activeCount: Int { agents.filter { $0.status == .working || $0.status == .claiming }.count }
    var doneCount: Int { agents.filter { $0.status == .done }.count }
    var failedCount: Int { agents.filter { $0.status == .failed }.count }

    var formattedElapsed: String {
        guard let start = startTime else { return "0:00" }
        let secs = Int(Date().timeIntervalSince(start))
        return String(format: "%d:%02d", secs / 60, secs % 60)
    }

    init(basePath: String? = nil, runId: String = "") {
        self.basePath = basePath ?? (FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".copilot/stampede").path)
        self.runId = runId.isEmpty ? (Self.latestRunId(in: self.basePath) ?? "") : runId
    }

    func startMonitoring() {
        isRunning = true
        startTime = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        isRunning = false
    }

    func refresh() {
        guard !runId.isEmpty else { return }
        let runDir = URL(fileURLWithPath: basePath).appendingPathComponent(runId)
        readFileSystemState(runDir: runDir)
    }

    private func readFileSystemState(runDir: URL) {
        let queueDir   = runDir.appendingPathComponent("queue")
        let claimedDir = runDir.appendingPathComponent("claimed")
        let resultsDir = runDir.appendingPathComponent("results")
        let pidsDir    = runDir.appendingPathComponent("pids")
        let fleetFile  = runDir.appendingPathComponent("fleet.json")

        let fleet = loadFleet(file: fleetFile)
        let pids = loadPids(dir: pidsDir)
        let claimedBy = claimedWorkers(dir: claimedDir)

        var updated: [Agent] = []
        for worker in fleet {
            let pid = pids[worker.name]
            let alive = pid.flatMap { isPidAlive($0) } ?? false
            let isClaimed = claimedBy.contains(worker.name)

            let status: AgentStatus
            if !alive && pid != nil { status = .failed }
            else if isClaimed       { status = .working }
            else                    { status = .idle }

            updated.append(Agent(
                id: worker.name, name: worker.name, model: worker.model,
                status: status, task: "", branch: "stampede/\(worker.name)",
                progress: status == .done ? 1.0 : 0.5,
                tokensUsed: 0, elapsedSeconds: 0,
                activity: status == .working ? "Processing..." : status.label,
                pid: pid.map(Int.init)
            ))
        }

        self.agents = updated
        self.doneTasks = countJSON(dir: resultsDir)
        let queueCount = countJSON(dir: queueDir)
        self.totalTasks = queueCount + updated.count + doneTasks

        NSApp.dockTile.badgeLabel = activeCount > 0 ? "\(activeCount)" : nil
    }

    private struct FleetWorker { let name: String; let model: String; let slot: Int }

    private func loadFleet(file: URL) -> [FleetWorker] {
        guard let data = try? Data(contentsOf: file),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return [] }
        return obj.compactMap { key, val -> FleetWorker? in
            guard let dict = val as? [String: Any] else { return nil }
            let model = dict["model"] as? String ?? "unknown"
            let slot = dict["slot"] as? Int ?? 0
            return FleetWorker(name: key, model: model, slot: slot)
        }.sorted { $0.slot < $1.slot }
    }

    private func loadPids(dir: URL) -> [String: Int32] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return [:] }
        var out: [String: Int32] = [:]
        for f in files where f.pathExtension == "pid" {
            let name = f.deletingPathExtension().lastPathComponent
            if let s = try? String(contentsOf: f, encoding: .utf8),
               let pid = Int32(s.trimmingCharacters(in: .whitespacesAndNewlines)) {
                out[name] = pid
            }
        }
        return out
    }

    private func claimedWorkers(dir: URL) -> Set<String> {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return [] }
        var out: Set<String> = []
        for f in files where f.pathExtension == "json" {
            if let data = try? Data(contentsOf: f),
               let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
               let who = obj["claimed_by"] as? String {
                out.insert(who)
            }
        }
        return out
    }

    private func countJSON(dir: URL) -> Int {
        (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ))?.filter { $0.pathExtension == "json" && !$0.lastPathComponent.hasPrefix(".tmp-") }.count ?? 0
    }

    private func isPidAlive(_ pid: Int32) -> Bool {
        pid > 0 && kill(pid, 0) == 0
    }

    static func latestRunId(in basePath: String) -> String? {
        let baseURL = URL(fileURLWithPath: basePath)
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: baseURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ) else { return nil }
        return items
            .filter { $0.lastPathComponent.hasPrefix("run-") &&
                      ((try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false) }
            .map { $0.lastPathComponent }
            .sorted()
            .last
    }

    static func demo() -> StampedeState {
        let s = StampedeState()
        s.isRunning = true
        s.startTime = Date().addingTimeInterval(-312)
        s.totalTasks = 8
        s.doneTasks = 1
        s.agents = [
            Agent(id: "alpha", name: "alpha", model: "claude-haiku-4.5", status: .working,
                  task: "Implement JWT auth", branch: "stampede/jwt-auth",
                  progress: 0.67, tokensUsed: 142_300, elapsedSeconds: 245,
                  activity: "Editing auth/middleware.ts"),
            Agent(id: "bravo", name: "bravo", model: "claude-haiku-4.5", status: .working,
                  task: "Build REST API", branch: "stampede/api-endpoints",
                  progress: 0.45, tokensUsed: 98_700, elapsedSeconds: 187,
                  activity: "POST /api/users"),
            Agent(id: "charlie", name: "charlie", model: "claude-haiku-4.5", status: .done,
                  task: "Add DB migrations", branch: "stampede/db-migrations",
                  progress: 1.0, tokensUsed: 187_400, elapsedSeconds: 312,
                  activity: "14 migrations created"),
            Agent(id: "delta", name: "delta", model: "claude-haiku-4.5", status: .working,
                  task: "Create React dashboard", branch: "stampede/react-dash",
                  progress: 0.23, tokensUsed: 65_200, elapsedSeconds: 134,
                  activity: "Building StatusGrid"),
            Agent(id: "echo", name: "echo", model: "claude-haiku-4.5", status: .claiming,
                  task: "Set up CI/CD", branch: "stampede/cicd",
                  progress: 0.12, tokensUsed: 31_800, elapsedSeconds: 67,
                  activity: "Analyzing workflows"),
            Agent(id: "foxtrot", name: "foxtrot", model: "claude-haiku-4.5", status: .working,
                  task: "Write integration tests", branch: "stampede/tests",
                  progress: 0.78, tokensUsed: 156_900, elapsedSeconds: 289,
                  activity: "47/62 tests passing"),
            Agent(id: "golf", name: "golf", model: "claude-haiku-4.5", status: .failed,
                  task: "Configure Docker", branch: "stampede/docker",
                  progress: 0.0, tokensUsed: 0, elapsedSeconds: 0,
                  activity: "Port 5432 conflict"),
            Agent(id: "hotel", name: "hotel", model: "claude-haiku-4.5", status: .idle,
                  task: "Add WebSocket", branch: "stampede/websocket",
                  progress: 0.0, tokensUsed: 0, elapsedSeconds: 0,
                  activity: "Waiting for task"),
        ]
        s.conflicts = [
            FileConflict(filePath: "src/config/database.ts", agentIds: ["charlie", "foxtrot"], severity: .warning)
        ]
        return s
    }
}
