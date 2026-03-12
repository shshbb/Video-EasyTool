import Foundation

struct OpenAICompatibleClient {
    let baseURL: URL
    let apiKey: String

    init(baseURL: String, apiKey: String) throws {
        guard let url = URL(string: baseURL) else {
            throw AppError.invalidResponse("baseURL 无效: \(baseURL)")
        }
        self.baseURL = url
        self.apiKey = apiKey
    }

    func postJSON(path: String, json: [String: Any]) async throws -> Data {
        let url = resolvedURL(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: json)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AppError.invalidResponse("未返回 HTTP 响应")
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(decoding: data, as: UTF8.self)
            throw AppError.invalidResponse("status=\(http.statusCode), body=\(body)")
        }
        return data
    }

    func get(path: String) async throws -> Data {
        let url = resolvedURL(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AppError.invalidResponse("未返回 HTTP 响应")
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(decoding: data, as: UTF8.self)
            throw AppError.invalidResponse("status=\(http.statusCode), body=\(body)")
        }
        return data
    }

    func postMultipart(path: String, formData: MultipartFormData) async throws -> Data {
        let url = resolvedURL(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("multipart/form-data; boundary=\(formData.boundary)", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = formData.buildData()

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AppError.invalidResponse("未返回 HTTP 响应")
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(decoding: data, as: UTF8.self)
            throw AppError.invalidResponse("status=\(http.statusCode), body=\(body)")
        }
        return data
    }

    private func resolvedURL(path: String) -> URL {
        var normalized = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.hasPrefix("/") {
            normalized.removeFirst()
        }

        let baseEndsWithV1 = baseURL.path
            .split(separator: "/")
            .last?
            .lowercased() == "v1"
        let pathStartsWithV1 = normalized.lowercased().hasPrefix("v1/")

        if baseEndsWithV1 && pathStartsWithV1 {
            normalized = String(normalized.dropFirst(3))
        }

        return baseURL.appendingPathComponent(normalized)
    }
}

struct MultipartFormData {
    let boundary = "Boundary-\(UUID().uuidString)"
    private var parts: [Data] = []

    mutating func addText(name: String, value: String) {
        var s = ""
        s += "--\(boundary)\r\n"
        s += "Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n"
        s += "\(value)\r\n"
        parts.append(Data(s.utf8))
    }

    mutating func addFile(name: String, filename: String, mimeType: String, data: Data) {
        var header = ""
        header += "--\(boundary)\r\n"
        header += "Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n"
        header += "Content-Type: \(mimeType)\r\n\r\n"
        parts.append(Data(header.utf8))
        parts.append(data)
        parts.append(Data("\r\n".utf8))
    }

    func buildData() -> Data {
        var data = Data()
        for part in parts {
            data.append(part)
        }
        data.append(Data("--\(boundary)--\r\n".utf8))
        return data
    }
}
