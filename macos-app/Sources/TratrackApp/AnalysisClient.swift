import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2Posix
@preconcurrency import UserNotifications

/// One progress/terminal update pushed by the server on SubscribeAnalysis.
struct AnalysisUpdate: Sendable {
    var jobID: String
    var status: String
    var progress: Int
    var resultJSON: String
    var error: String
    var isFinished: Bool
    var isFailed: Bool
}

/// Talks to the tratrack analysis gRPC service (service/cmd/server).
/// StartAnalysis returns immediately with a job id; the server then *pushes*
/// updates on SubscribeAnalysis, so the UI is notified the moment the
/// 5-8 minute job finishes instead of polling StatusAnalysis.
struct AnalysisServiceClient: Sendable {
    var host = "localhost"
    var port = 50051

    /// Starts a job for `idFile` and calls `onUpdate` for every pushed event,
    /// returning after the terminal (COMPLETED/FAILED) event. Falls back to
    /// LastResult when the stream closes without delivering a terminal event,
    /// so the UI never gets stuck on "Analyze" after a successful run.
    func startAndWatch(idFile: String, onUpdate: @escaping @Sendable (AnalysisUpdate) async -> Void) async throws {
        dbg("connecting to \(host):\(port) for idFile=\(idFile)")

        let transport = try HTTP2ClientTransport.Posix(
            target: .dns(host: host, port: port),
            transportSecurity: .plaintext
        )

        try await withGRPCClient(transport: transport) { grpcClient in
            dbg("gRPC client ready")
            let service = Tratrack_Analysis_V1_AnalysisService.Client(wrapping: grpcClient)

            // Step 1: start the job
            var startRequest = Tratrack_Analysis_V1_StartAnalysisRequest()
            startRequest.idFile = idFile
            dbg("→ StartAnalysis(idFile: \(idFile))")
            let started = try await service.startAnalysis(startRequest)
            let jobID = started.jobID
            dbg("← StartAnalysis returned jobID=\(jobID) status=\(started.status)")

            // Step 2: subscribe to progress/completion push events
            var subscribeRequest = Tratrack_Analysis_V1_SubscribeAnalysisRequest()
            subscribeRequest.jobID = jobID
            dbg("→ SubscribeAnalysis(jobID: \(jobID)) — waiting for server events")

            let sawTerminal = SendableBox(false)
            try await service.subscribeAnalysis(subscribeRequest) { response in
                dbg("SubscribeAnalysis stream opened")
                var eventCount = 0
                for try await event in response.messages {
                    eventCount += 1
                    let isFinished = event.status == .completed
                    let isFailed = event.status == .failed
                    dbg("← event #\(eventCount): status=\(event.status) progress=\(event.progressPercent)% resultJson=\(event.resultJson.count) chars isFinished=\(isFinished) isFailed=\(isFailed)")
                    if isFinished || isFailed { sawTerminal.value = true }
                    await onUpdate(AnalysisUpdate(
                        jobID: event.jobID,
                        status: "\(event.status)",
                        progress: Int(event.progressPercent),
                        resultJSON: event.resultJson,
                        error: event.error,
                        isFinished: isFinished,
                        isFailed: isFailed
                    ))
                }
                dbg("SubscribeAnalysis stream closed after \(eventCount) event(s), sawTerminal=\(sawTerminal.value)")
            }
            dbg("subscribeAnalysis completed for jobID=\(jobID) sawTerminal=\(sawTerminal.value)")

            // Fallback: if the stream ended without a terminal event, fetch the
            // final state via LastResult so the UI still gets the ticket.
            if !sawTerminal.value {
                dbg("no terminal event received — calling LastResult as fallback")
                let last = try await service.lastResult(Tratrack_Analysis_V1_LastResultRequest())
                let isFinished = last.status == .completed
                let isFailed = last.status == .failed
                dbg("← LastResult jobID=\(last.jobID) status=\(last.status) resultJson=\(last.resultJson.count) chars")
                await onUpdate(AnalysisUpdate(
                    jobID: last.jobID,
                    status: "\(last.status)",
                    progress: isFinished ? 100 : 0,
                    resultJSON: last.resultJson,
                    error: "",
                    isFinished: isFinished,
                    isFailed: isFailed
                ))
            }
        }
        dbg("withGRPCClient block exited — startAndWatch done")
    }

    /// Mutable box for tracking stream state from inside a @Sendable closure.
    private final class SendableBox<T>: @unchecked Sendable {
        var value: T
        init(_ value: T) { self.value = value }
    }

    /// Calls the CallStories RPC with a YAML order string and returns the result string.
    func callStories(order: String) async throws -> String {
        dbg("callStories → \(order.prefix(80).replacingOccurrences(of: "\n", with: "\\n"))")

        let transport = try HTTP2ClientTransport.Posix(
            target: .dns(host: host, port: port),
            transportSecurity: .plaintext
        )

        return try await withGRPCClient(transport: transport) { grpcClient in
            let service = Tratrack_Analysis_V1_AnalysisService.Client(wrapping: grpcClient)
            var req = Tratrack_Analysis_V1_CallStoriesRequest()
            req.order = order
            dbg("→ callStories(order \(order.utf8.count) bytes)")
            let resp = try await service.callStories(req)
            dbg("← callStories result \(resp.result.count) chars")
            return resp.result
        }
    }
}

// MARK: - helpers

private func dbg(_ message: String, file: String = #file, line: Int = #line) {
    let src = URL(fileURLWithPath: file).lastPathComponent
    print("[GRPC \(src):\(line)] \(message)")
}

/// Posts a macOS banner notification when an analysis finishes.
enum AnalysisNotifier {
    static func notifyFinished(jobID: String, failed: Bool) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = failed ? "Analysis failed" : "Analysis finished"
            content.body = failed
                ? "The analysis job \(jobID) failed."
                : "Your analysis is ready (job \(jobID))."
            content.sound = .default
            center.add(UNNotificationRequest(
                identifier: "analysis-\(jobID)",
                content: content,
                trigger: nil
            ))
        }
    }
}
