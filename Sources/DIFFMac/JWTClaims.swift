import Foundation

enum JWTClaims {
    static func payload(from token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 {
            payload.append("=")
        }
        guard
            let data = Data(base64Encoded: payload),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        return json
    }

    static func subject(from token: String) -> String? {
        payload(from: token)?["sub"] as? String
    }

    static func expirationDate(from token: String) -> Date? {
        guard let exp = payload(from: token)?["exp"] else {
            return nil
        }
        if let seconds = exp as? TimeInterval {
            return Date(timeIntervalSince1970: seconds)
        }
        if let seconds = exp as? Int {
            return Date(timeIntervalSince1970: TimeInterval(seconds))
        }
        return nil
    }

    static func isExpiredOrExpiringSoon(_ token: String, now: Date = Date(), leeway: TimeInterval = 300) -> Bool {
        guard let expiration = expirationDate(from: token) else {
            return false
        }
        return expiration.timeIntervalSince(now) <= leeway
    }
}
