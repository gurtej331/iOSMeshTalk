import Foundation

/// Mirrors com.example.data.Message exactly, field-for-field, so JSON
/// produced by either platform decodes correctly on the other.
struct MeshMessage: Identifiable, Codable, Equatable {
    let id: String
    let senderNickname: String
    let body: String
    let timestamp: Int64
    var ttl: Int
    var hopCount: Int

    init(id: String = UUID().uuidString,
         senderNickname: String,
         body: String,
         timestamp: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
         ttl: Int = 5,
         hopCount: Int = 0) {
        self.id = id
        self.senderNickname = senderNickname
        self.body = body
        self.timestamp = timestamp
        self.ttl = ttl
        self.hopCount = hopCount
    }

    func toJSONData() -> Data? {
        try? JSONEncoder().encode(self)
    }

    static func from(jsonData: Data) -> MeshMessage? {
        try? JSONDecoder().decode(MeshMessage.self, from: jsonData)
    }
}
