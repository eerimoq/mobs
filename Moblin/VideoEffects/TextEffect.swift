import AVFoundation
import Collections
import MetalPetal
import SwiftUI
import UIKit
import Vision
import WeatherKit

private let textQueue = DispatchQueue(label: "com.eerimoq.widget.text")

struct TextEffectStats {
    var timestamp: ContinuousClock.Instant
    var bitrateAndTotal: String
    var date: Date
    var debugOverlayLines: [String]
    var speed: String
    var altitude: String
    var distance: String
    var conditions: String?
    var temperature: Measurement<UnitTemperature>?
    var countryFlag: String?
    var city: String?
}

private enum PartData: Equatable {
    case text(String)
    case imageSystemName(String)
}

private struct Part: Equatable, Identifiable {
    var id: Int
    var data: PartData
}

private struct Line: Equatable, Identifiable {
    var id: Int
    var parts: [Part]
}

final class TextEffect: VideoEffect {
    private let filter = CIFilter.sourceOverCompositing()
    private var backgroundColor: RgbColor?
    private var foregroundColor: RgbColor?
    private let fontSize: CGFloat
    private let fontDesign: Font.Design
    private let fontWeight: Font.Weight
    private var x: Double
    private var y: Double
    private let settingName: String
    private var stats: Deque<TextEffectStats> = []
    private var formatParts: [TextFormatPart]
    private var overlay: CIImage?
    private var overlayMetalPetal: MTIImage?
    private var image: UIImage?
    private var imageMetalPetal: UIImage?
    private var nextUpdateTime = ContinuousClock.now
    private var nextUpdateTimeMetalPetal = ContinuousClock.now
    private var previousLines: [Line]?
    private var previousLinesMetalPetal: [Line]?
    private var delay: Double
    private var previousX: Double = .nan
    private var previousXMetalPetal: Double = .nan
    private var previousY: Double = .nan
    private var previousYMetalPetal: Double = .nan
    private var previousForegroundColor: RgbColor?
    private var previousForegroundColorMetalPetal: RgbColor?
    private var previousBackgroundColor: RgbColor?
    private var previousBackgroundColorMetalPetal: RgbColor?
    private var timersEndTime: [ContinuousClock.Instant]
    private let temperatureFormatter = MeasurementFormatter()

    init(
        format: String,
        backgroundColor: RgbColor,
        foregroundColor: RgbColor,
        fontSize: CGFloat,
        fontDesign: Font.Design,
        fontWeight: Font.Weight,
        settingName: String,
        delay: Double,
        timersEndTime: [ContinuousClock.Instant]
    ) {
        formatParts = loadTextFormat(format: format)
        self.backgroundColor = backgroundColor
        self.foregroundColor = foregroundColor
        self.fontSize = fontSize
        self.fontDesign = fontDesign
        self.fontWeight = fontWeight
        self.settingName = settingName
        self.delay = delay
        x = 0
        y = 0
        self.timersEndTime = timersEndTime
        temperatureFormatter.numberFormatter.maximumFractionDigits = 0
        super.init()
    }

    func setBackgroundColor(color: RgbColor) {
        textQueue.sync {
            backgroundColor = color
        }
        previousLines = nil
        previousLinesMetalPetal = nil
    }

    func setForegroundColor(color: RgbColor) {
        textQueue.sync {
            foregroundColor = color
        }
        previousLines = nil
        previousLinesMetalPetal = nil
    }

    func setEndTime(index: Int, endTime: ContinuousClock.Instant) {
        guard index < timersEndTime.count else {
            return
        }
        timersEndTime[index] = endTime
    }

    func setPosition(x: Double, y: Double) {
        textQueue.sync {
            self.x = x
            self.y = y
        }
        previousLines = nil
        previousLinesMetalPetal = nil
    }

    func updateStats(stats: TextEffectStats) {
        self.stats.append(stats)
        if self.stats.count > 10 {
            self.stats.removeFirst()
        }
    }

    override func getName() -> String {
        return "\(settingName) text widget"
    }

    private func formatted(now: ContinuousClock.Instant) -> [Line] {
        guard let stats = stats
            .last(where: { $0.timestamp.advanced(by: .seconds(delay - 1)) <= now }) ?? stats
            .first
        else {
            return []
        }
        var timerIndex = 0
        var lines: [Line] = []
        var parts: [Part] = []
        var lineId = 0
        var partId = 0
        for formatPart in formatParts {
            switch formatPart {
            case let .text(text):
                parts.append(.init(id: partId, data: .text(text)))
            case .newLine:
                lines.append(.init(id: lineId, parts: parts))
                lineId += 1
                parts = []
            case .clock:
                parts.append(.init(
                    id: partId,
                    data: .text(stats.date.formatted(.dateTime.hour().minute().second()))
                ))
            case .bitrateAndTotal:
                parts.append(.init(id: partId, data: .text(stats.bitrateAndTotal)))
            case .debugOverlay:
                parts.append(.init(
                    id: partId,
                    data: .text(stats.debugOverlayLines.joined(separator: "\n"))
                ))
            case .speed:
                parts.append(.init(id: partId, data: .text(stats.speed)))
            case .altitude:
                parts.append(.init(id: partId, data: .text(stats.altitude)))
            case .distance:
                parts.append(.init(id: partId, data: .text(stats.distance)))
            case .timer:
                if timerIndex < timersEndTime.count {
                    let timeLeft = max(now.duration(to: timersEndTime[timerIndex]).seconds, 0)
                    parts.append(.init(
                        id: partId,
                        data: .text(uptimeFormatter.string(from: Double(timeLeft)) ?? "")
                    ))
                }
                timerIndex += 1
            case .conditions:
                if let conditions = stats.conditions {
                    parts.append(.init(id: partId, data: .imageSystemName(conditions)))
                } else {
                    parts.append(.init(id: partId, data: .text("-")))
                }
            case .temperature:
                if let temperature = stats.temperature {
                    parts.append(.init(
                        id: partId,
                        data: .text(temperatureFormatter.string(from: temperature))
                    ))
                } else {
                    parts.append(.init(id: partId, data: .text("-")))
                }
            case .countryFlag:
                parts.append(.init(id: partId, data: .text(stats.countryFlag ?? "-")))
            case .city:
                parts.append(.init(id: partId, data: .text(stats.city ?? "-")))
            }
            partId += 1
        }
        if !parts.isEmpty {
            lines.append(.init(id: lineId, parts: parts))
        }
        return lines
    }

    private func scaledFontSize(width: Double) -> CGFloat {
        return fontSize * (width / 1920)
    }

    private func updateOverlay(size: CGSize) {
        let now = ContinuousClock.now
        var newImage: UIImage?
        let (x, y, foregroundColor, backgroundColor) = textQueue.sync {
            if self.image != nil {
                newImage = self.image
                self.image = nil
            }
            return (self.x, self.y, self.foregroundColor, self.backgroundColor)
        }
        if let newImage {
            let x = toPixels(x, size.width)
            let y = toPixels(y, size.height)
            overlay = CIImage(image: newImage)?
                .transformed(by: CGAffineTransform(
                    translationX: x,
                    y: size.height - newImage.size.height - y
                ))
                .cropped(to: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        }
        guard now >= nextUpdateTime || x != previousX || y != previousY || previousForegroundColor !=
            foregroundColor || previousBackgroundColor != backgroundColor
        else {
            return
        }
        previousX = x
        previousY = y
        previousForegroundColor = foregroundColor
        previousBackgroundColor = backgroundColor
        nextUpdateTime += .seconds(1)
        DispatchQueue.main.async {
            let lines = self.formatted(now: now)
            guard lines != self.previousLines else {
                return
            }
            self.previousLines = lines
            let text = VStack(alignment: .leading) {
                ForEach(lines) { line in
                    HStack(spacing: 0) {
                        ForEach(line.parts) { part in
                            switch part.data {
                            case let .text(text):
                                Text(text)
                                    .foregroundColor(self.foregroundColor?.color() ?? .clear)
                            case let .imageSystemName(name):
                                if UIImage(systemName: "\(name).fill") != nil {
                                    Image(systemName: "\(name).fill")
                                        .symbolRenderingMode(.multicolor)
                                } else {
                                    Image(systemName: name)
                                        .foregroundColor(self.foregroundColor?.color() ?? .clear)
                                }
                            }
                        }
                    }
                }
            }
            .padding([.leading, .trailing], 7)
            .background(self.backgroundColor?.color() ?? .clear)
            .font(.system(
                size: self.scaledFontSize(width: size.width),
                weight: self.fontWeight,
                design: self.fontDesign
            ))
            .cornerRadius(10)
            let renderer = ImageRenderer(content: text)
            let image = renderer.uiImage
            textQueue.sync {
                self.image = image
            }
        }
    }

    private func updateOverlayMetalPetal(size: CGSize) -> (Double, Double) {
        let now = ContinuousClock.now
        var newImage: UIImage?
        let (x, y, foregroundColor, backgroundColor) = textQueue.sync {
            if self.imageMetalPetal != nil {
                newImage = self.imageMetalPetal
                self.imageMetalPetal = nil
            }
            return (self.x, self.y, self.foregroundColor, self.backgroundColor)
        }
        if let image = newImage?.cgImage {
            overlayMetalPetal = MTIImage(cgImage: image, isOpaque: true)
        }
        guard now >= nextUpdateTimeMetalPetal || x != previousXMetalPetal || y != previousYMetalPetal ||
            previousForegroundColorMetalPetal != foregroundColor || previousBackgroundColorMetalPetal !=
            backgroundColor
        else {
            return (x, y)
        }
        previousXMetalPetal = x
        previousYMetalPetal = y
        previousForegroundColorMetalPetal = foregroundColor
        previousBackgroundColorMetalPetal = backgroundColor
        nextUpdateTimeMetalPetal += .seconds(1)
        DispatchQueue.main.async {
            let lines = self.formatted(now: now)
            guard lines != self.previousLinesMetalPetal else {
                return
            }
            self.previousLinesMetalPetal = lines
            let text = VStack(alignment: .leading) {
                ForEach(lines) { line in
                    HStack {
                        ForEach(line.parts) { part in
                            switch part.data {
                            case let .text(text):
                                Text(text)
                                    .foregroundColor(self.foregroundColor?.color() ?? .clear)
                            case let .imageSystemName(name):
                                if UIImage(systemName: "\(name).fill") != nil {
                                    Image(systemName: "\(name).fill")
                                        .symbolRenderingMode(.multicolor)
                                } else {
                                    Image(systemName: name)
                                        .foregroundColor(self.foregroundColor?.color() ?? .clear)
                                }
                            }
                        }
                    }
                }
            }
            .padding([.leading, .trailing], 7)
            .background(self.backgroundColor?.color() ?? .clear)
            .font(.system(
                size: self.scaledFontSize(width: size.width),
                weight: self.fontWeight,
                design: self.fontDesign
            ))
            .cornerRadius(10)
            let renderer = ImageRenderer(content: text)
            let image = renderer.uiImage
            textQueue.sync {
                self.imageMetalPetal = image
            }
        }
        return (x, y)
    }

    override func execute(_ image: CIImage, _: [VNFaceObservation]?, _: Bool) -> CIImage {
        updateOverlay(size: image.extent.size)
        filter.inputImage = overlay
        filter.backgroundImage = image
        return filter.outputImage ?? image
    }

    override func executeMetalPetal(_ image: MTIImage?, _: [VNFaceObservation]?, _: Bool) -> MTIImage? {
        guard let image else {
            return image
        }
        var (x, y) = updateOverlayMetalPetal(size: image.size)
        guard let overlayMetalPetal else {
            return image
        }
        x = toPixels(x, image.size.width) + overlayMetalPetal.size.width / 2
        y = toPixels(y, image.size.height) + overlayMetalPetal.size.height / 2
        let filter = MTIMultilayerCompositingFilter()
        filter.inputBackgroundImage = image
        filter.layers = [
            .init(content: overlayMetalPetal, position: .init(x: x, y: y)),
        ]
        return filter.outputImage ?? image
    }
}
