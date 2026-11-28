import Foundation

/// Stored radio previews use the same occurrence and acquisition fields as the Inbox.
public struct RadioMix: Decodable, Sendable {
    public let state: String
    public let previewID: String?
    public let kind: String?
    public let title: String?
    public let totalCount: Int?
    public let ownedCount: Int?
    public let tracks: [PlaylistInboxTrack]

    enum CodingKeys: String, CodingKey {
        case state, kind, title, tracks
        case previewID = "preview_id", totalCount = "total_count", ownedCount = "owned_count"
    }
}

public struct RadioMixRequest: Encodable, Equatable, Sendable {
    public enum Kind: String, Encodable, Sendable { case artist, discovery }
    public let kind: Kind
    public let artistMBID: String?
    public let tag: String?
    public let familiarity: String
    public let mode: String

    public init(kind: Kind, artistMBID: String? = nil, tag: String? = nil,
                familiarity: String = "familiar", mode: String = "easy") {
        self.kind = kind; self.artistMBID = artistMBID; self.tag = tag
        self.familiarity = familiarity; self.mode = mode
    }

    enum CodingKeys: String, CodingKey {
        case kind, tag, familiarity, mode
        case artistMBID = "artist_mbid"
    }
}

extension LibrarianClient {
    public func previewRadioMix(_ request: RadioMixRequest) async throws -> RadioMix {
        let (data, http) = try await authedSendPublic("POST", "api/radio-mixes/preview", body: JSONEncoder().encode(request))
        return try decodePublic(RadioMix.self, data, http)
    }

    public func radioMix(id: String) async throws -> RadioMix {
        let (data, http) = try await authedSendPublic("GET", "api/radio-mixes/\(id)", body: nil)
        return try decodePublic(RadioMix.self, data, http)
    }

    public func downloadRadioMixTrack(id: String, position: Int) async throws -> PlaylistInboxDownload {
        let (data, http) = try await authedSendPublic("POST", "api/radio-mixes/\(id)/tracks/\(position)/download", body: nil)
        return try decodePublic(PlaylistInboxDownload.self, data, http)
    }
}
