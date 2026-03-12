import Foundation

enum AppError: LocalizedError {
    case toolNotFound(String)
    case processFailed(String)
    case invalidResponse(String)
    case parseFailed(String)
    case ioFailed(String)

    var errorDescription: String? {
        switch self {
        case .toolNotFound(let tool):
            return "未找到工具: \(tool)"
        case .processFailed(let detail):
            return "命令执行失败: \(detail)"
        case .invalidResponse(let detail):
            return "接口返回异常: \(detail)"
        case .parseFailed(let detail):
            return "解析失败: \(detail)"
        case .ioFailed(let detail):
            return "读写失败: \(detail)"
        }
    }
}
