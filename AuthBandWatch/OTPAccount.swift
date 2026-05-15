import Foundation

struct OTPAccount: Codable, Identifiable, Hashable {
    let id: UUID
    let issuer: String
    let name: String
    let secret: String
    let digits: Int
    let period: TimeInterval

    init(
        id: UUID = UUID(),
        issuer: String,
        name: String,
        secret: String,
        digits: Int = 6,
        period: TimeInterval = 30
    ) {
        self.id = id
        self.issuer = issuer
        self.name = name
        self.secret = secret
        self.digits = digits
        self.period = period
    }
}
