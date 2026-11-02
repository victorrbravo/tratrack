import Foundation

enum UploadError: LocalizedError {
    case notMP4
    case noAPIKey
    case serverError(Int, String)
    case emptyID(String)

    var errorDescription: String? {
        switch self {
        case .notMP4:          return "Only .mp4 files are accepted"
        case .noAPIKey:        return "Muse API key not set — open Settings first"
        case .serverError(let code, let body): return "Upload failed (\(code)): \(body)"
        case .emptyID(let body):               return "Upload response missing file ID: \(body)"
        }
    }
}

/// Uploads an mp4 video to the Muse Files API and returns the resulting file_id.
/// Mirrors service/commands/upload.go.
struct UploadClient: Sendable {
    var apiKey: String

    private static let apiBase = "https://api.meta.ai/v1"
    private static let expirySeconds = "3600"

    func upload(videoURL: URL) async throws -> String {
        print("[Upload] starting upload of \(videoURL.lastPathComponent)")

        let boundary = "Boundary-\(UUID().uuidString)"
        let body = try buildMultipartBody(videoURL: videoURL, boundary: boundary)
        print("[Upload] multipart body built: \(body.count) bytes")

        var request = URLRequest(url: URL(string: "\(UploadClient.apiBase)/files")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.upload(for: request, from: body)

        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        let responseBody = String(data: data, encoding: .utf8) ?? ""
        print("[Upload] HTTP \(http.statusCode)  response: \(responseBody.prefix(200))")

        guard (200..<300).contains(http.statusCode) else {
            throw UploadError.serverError(http.statusCode, responseBody)
        }

        struct UploadedFile: Decodable { var id: String }
        let uploaded = try JSONDecoder().decode(UploadedFile.self, from: data)
        guard !uploaded.id.isEmpty else {
            throw UploadError.emptyID(responseBody)
        }
        print("[Upload] ✓ fileID=\(uploaded.id)")
        return uploaded.id
    }

    private func buildMultipartBody(videoURL: URL, boundary: String) throws -> Data {
        var body = Data()
        func append(_ s: String) { body.append(Data(s.utf8)) }

        let fields: [(String, String)] = [
            ("purpose",                  "user_data"),
            ("expires_after[anchor]",    "created_at"),
            ("expires_after[seconds]",   UploadClient.expirySeconds),
        ]
        for (name, value) in fields {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            append("\(value)\r\n")
        }

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(videoURL.lastPathComponent)\"\r\n")
        append("Content-Type: video/mp4\r\n\r\n")
        body.append(try Data(contentsOf: videoURL))
        append("\r\n--\(boundary)--\r\n")

        return body
    }
}
