import Foundation

class MoblinSettingsWebBrowser: Codable {
    var home: String?
}

class MoblinSettingsSrt: Codable {
    var latency: Int32?
    var adaptiveBitrateEnabled: Bool?
}

class MoblinSettingsUrlStreamVideo: Codable {
    var codec: SettingsStreamCodec?
}

class MoblinSettingsUrlStreamObs: Codable {
    var webSocketUrl: String
    var webSocketPassword: String
}

class MoblinSettingsUrlStream: Codable {
    var name: String
    var url: String
    var enabled: Bool?
    var video: MoblinSettingsUrlStreamVideo?
    var srt: MoblinSettingsSrt?
    var obs: MoblinSettingsUrlStreamObs?
}

class MoblinSettingsButton: Codable {
    var type: SettingsButtonType
    var enabled: Bool?
}

class MoblinQuickButtons: Codable {
    var twoColumns: Bool?
    var showName: Bool?
    var enableScroll: Bool?
    // Use "buttons" to enable buttons after disabling all.
    var disableAllButtons: Bool?
    var buttons: [MoblinSettingsButton]?
}

class MoblinSettingsUrl: Codable {
    // The last enabled stream will be selected (if any).
    var streams: [MoblinSettingsUrlStream]?
    var quickButtons: MoblinQuickButtons?
    var webBrowser: MoblinSettingsWebBrowser?

    static func fromString(query: String) throws -> MoblinSettingsUrl {
        let query = try JSONDecoder().decode(
            MoblinSettingsUrl.self,
            from: query.data(using: .utf8)!
        )
        for stream in query.streams ?? [] {
            if let message = isValidUrl(url: cleanUrl(url: stream.url)) {
                throw message
            }
            if let srt = stream.srt {
                if let latency = srt.latency {
                    if latency < 0 {
                        throw "Negative SRT latency"
                    }
                }
            }
            if let obs = stream.obs {
                if let message = isValidWebSocketUrl(url: cleanUrl(url: obs.webSocketUrl)) {
                    throw message
                }
            }
        }
        return query
    }
}
