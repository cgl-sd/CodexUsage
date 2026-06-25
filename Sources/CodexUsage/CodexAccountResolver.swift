import Foundation

public struct CodexAccountInfo: Sendable, Equatable {
    public let email: String?
    public let name: String?
    public let accountID: String?
    public let planType: String?
    public let authMode: String?
    public let verification: AccountVerification

    public static let unknown = CodexAccountInfo(
        email: nil,
        name: nil,
        accountID: nil,
        planType: nil,
        authMode: nil,
        verification: .missingLocalAuth
    )
}

public enum AccountVerification: Sendable, Equatable {
    case verifiedLocalAuth
    case missingLocalAuth
}

public struct CodexAccountResolver: Sendable {
    public let authFile: URL

    public init(authFile: URL? = nil) {
        if let authFile {
            self.authFile = authFile
        } else {
            self.authFile = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex/auth.json")
        }
    }

    public func resolve() -> CodexAccountInfo {
        localAuthAccountInfo()
    }

    public func localAuthAccountInfo() -> CodexAccountInfo {
        guard let data = try? Data(contentsOf: authFile),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .unknown
        }

        let authMode = root["auth_mode"] as? String
        let tokens = root["tokens"] as? [String: Any]
        let idPayload = decodeJWTPayload(tokens?["id_token"] as? String)
        let accessPayload = decodeJWTPayload(tokens?["access_token"] as? String)
        let idAuth = idPayload?["https://api.openai.com/auth"] as? [String: Any]
        let accessAuth = accessPayload?["https://api.openai.com/auth"] as? [String: Any]
        let profile = accessPayload?["https://api.openai.com/profile"] as? [String: Any]

        return CodexAccountInfo(
            email: idPayload?["email"] as? String ?? profile?["email"] as? String,
            name: idPayload?["name"] as? String,
            accountID: tokens?["account_id"] as? String
                ?? accessAuth?["chatgpt_account_id"] as? String
                ?? idAuth?["chatgpt_account_id"] as? String,
            planType: accessAuth?["chatgpt_plan_type"] as? String
                ?? idAuth?["chatgpt_plan_type"] as? String,
            authMode: authMode,
            verification: .verifiedLocalAuth
        )
    }

    private func decodeJWTPayload(_ token: String?) -> [String: Any]? {
        guard let token else { return nil }
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }

        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = (4 - payload.count % 4) % 4
        payload.append(String(repeating: "=", count: padding))

        guard let data = Data(base64Encoded: payload),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }
}
