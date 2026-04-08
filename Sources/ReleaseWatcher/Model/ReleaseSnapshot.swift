import Foundation

struct ReleaseSnapshot: Identifiable, Codable, Hashable {
    let id: UUID
    var tagName: String
    var releaseName: String?
    var publishedAt: Date?
    var htmlURL: URL?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        tagName: String,
        releaseName: String? = nil,
        publishedAt: Date? = nil,
        htmlURL: URL? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.tagName = tagName
        self.releaseName = releaseName
        self.publishedAt = publishedAt
        self.htmlURL = htmlURL
        self.createdAt = createdAt
    }
}
