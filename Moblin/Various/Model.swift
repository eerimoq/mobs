import AlertToast
import Collections
import Combine
import CoreMotion
import GameController
import MapKit
import NaturalLanguage
import Network
import NetworkExtension
import PhotosUI
import ReplayKit
import SDWebImageSwiftUI
import SDWebImageWebPCoder
import StoreKit
import SwiftUI
import TwitchChat
import VideoToolbox
import WatchConnectivity
import WebKit

class Browser: Identifiable {
    var id: UUID = .init()
    var browserEffect: BrowserEffect

    init(browserEffect: BrowserEffect) {
        self.browserEffect = browserEffect
    }
}

private let maximumNumberOfChatMessages = 50
private let secondsSuffix = String(localized: "/sec")
private let fallbackStream = SettingsStream(name: "Fallback")
let fffffMessage = String(localized: "😢 FFFFF 😢")
let lowBitrateMessage = String(localized: "Low bitrate")
let lowBatteryMessage = String(localized: "Low battery")

func formatWarning(_ message: String) -> String {
    return "⚠️ \(message) ⚠️"
}

func failedToConnectMessage(_ name: String) -> String {
    return String(localized: "😢 Failed to connect to \(name) 😢")
}

struct Camera: Identifiable, Equatable {
    var id: String
    var name: String
}

struct Mic: Identifiable, Hashable {
    var id: String {
        "\(inputUid) \(dataSourceID ?? 0)"
    }

    var name: String
    var inputUid: String
    var dataSourceID: NSNumber?
    var builtInOrientation: SettingsMic?
}

struct Icon: Identifiable {
    var name: String
    var id: String
    var price: String

    func imageNoBackground() -> String {
        return "\(id)NoBackground"
    }

    func image() -> String {
        return id
    }
}

let plainIcon = Icon(name: "Plain", id: "AppIcon", price: "")
private let noMic = Mic(name: "", inputUid: "")

private let globalMyIcons = [
    plainIcon,
    Icon(name: "Halloween", id: "AppIconHalloween", price: "$"),
    Icon(
        name: "Halloween pumpkin",
        id: "AppIconHalloweenPumpkin",
        price: ""
    ),
]

private let iconsProductIds = [
    "AppIconKing",
    "AppIconQueen",
    "AppIconHeart",
    "AppIconLooking",
    "AppIconGoblin",
    "AppIconGoblina",
    "AppIconTetris",
    "AppIconTub",
    "AppIconMillionaire",
    "AppIconBillionaire",
    "AppIconTrillionaire",
    "AppIconIreland",
]

struct ChatMessageEmote: Identifiable {
    var id = UUID()
    var url: URL
    var range: ClosedRange<Int>
}

struct ChatPostSegment: Identifiable {
    var id = UUID()
    var text: String?
    var url: URL?
}

func makeChatPostTextSegments(text: String) -> [ChatPostSegment] {
    var segments: [ChatPostSegment] = []
    for word in text.split(separator: " ") {
        segments.append(ChatPostSegment(
            text: "\(word) "
        ))
    }
    return segments
}

struct ChatPost: Identifiable, Equatable {
    static func == (lhs: ChatPost, rhs: ChatPost) -> Bool {
        return lhs.id == rhs.id
    }

    var id: Int
    var user: String?
    var userColor: String?
    var segments: [ChatPostSegment]
    var timestamp: String
    var timestampTime: ContinuousClock.Instant
    var isAction: Bool
    var isAnnouncement: Bool
    var isFirstMessage: Bool
    var isSubscriber: Bool
}

class ButtonState {
    var isOn: Bool
    var button: SettingsButton

    init(isOn: Bool, button: SettingsButton) {
        self.isOn = isOn
        self.button = button
    }
}

enum StreamState {
    case connecting
    case connected
    case disconnected
}

struct ButtonPair: Identifiable, Equatable {
    static func == (lhs: ButtonPair, rhs: ButtonPair) -> Bool {
        return lhs.id == rhs.id
    }

    var id: UUID
    var first: ButtonState
    var second: ButtonState?
}

struct LogEntry: Identifiable {
    var id: Int
    var message: String
}

enum WizardPlatform {
    case twitch
    case kick
    case youTube
    case afreecaTv
    case custom
}

enum WizardNetworkSetup {
    case none
    case obs
    case belaboxCloudObs
    case irlToolkit
    case direct
    case myServers
}

enum WizardCustomProtocol {
    case none
    case srt
    case rtmp
    case rist

    func toDefaultCodec() -> SettingsStreamCodec {
        switch self {
        case .none:
            return .h264avc
        case .srt:
            return .h265hevc
        case .rtmp:
            return .h264avc
        case .rist:
            return .h265hevc
        }
    }
}

final class Model: NSObject, ObservableObject {
    private let media = Media()
    var streamState = StreamState.disconnected {
        didSet {
            logger.info("stream: State \(oldValue) -> \(streamState)")
        }
    }

    @Published var scrollQuickButtons: Int = 0
    @Published var bias: Float = 0.0

    private var manualFocusesEnabled: [AVCaptureDevice: Bool] = [:]
    private var manualFocuses: [AVCaptureDevice: Float] = [:]
    @Published var manualFocus: Float = 1.0
    @Published var manualFocusEnabled = false
    var editingManualFocus = false
    private var focusObservation: NSKeyValueObservation?
    @Published var manualFocusPoint: CGPoint?

    private var manualIsosEnabled: [AVCaptureDevice: Bool] = [:]
    private var manualIsos: [AVCaptureDevice: Float] = [:]
    @Published var manualIso: Float = 1.0
    @Published var manualIsoEnabled = false
    var editingManualIso = false
    private var isoObservation: NSKeyValueObservation?

    private var manualWhiteBalancesEnabled: [AVCaptureDevice: Bool] = [:]
    private var manualWhiteBalances: [AVCaptureDevice: Float] = [:]
    @Published var manualWhiteBalance: Float = 0
    @Published var manualWhiteBalanceEnabled = false
    var editingManualWhiteBalance = false
    private var whiteBalanceObservation: NSKeyValueObservation?

    private var manualFocusMotionAttitude: CMAttitude?
    @Published var showingSettings = false
    @Published var showingCosmetics = false
    @Published var settingsLayout: SettingsLayout = .right
    @Published var showChatMessages = true
    @Published var chatPaused = false
    @Published var interactiveChat = false
    @Published var blackScreen = false
    @Published var findFace = false
    private var findFaceTimer: Timer?
    private var streaming = false
    @Published var currentMic = noMic
    private var micChange = noMic
    private var streamStartTime: ContinuousClock.Instant?
    @Published var isLive = false
    @Published var isRecording = false
    private var currentRecording: Recording?
    @Published var recordingLength = noValue
    @Published var browserWidgetsStatus = noValue
    private var browserWidgetsStatusChanged = false
    private var subscriptions = Set<AnyCancellable>()
    @Published var uptime = noValue
    @Published var bondingStatistics = noValue
    @Published var audioLevel: Float = defaultAudioLevel
    @Published var numberOfAudioChannels: Int = 0
    var settings = Settings()
    @Published var digitalClock = noValue
    private var selectedSceneId = UUID()
    private var twitchChat: TwitchChatMoblin!
    private var twitchPubSub: TwitchPubSub?
    private var kickPusher: KickPusher?
    private var kickViewers: KickViewers?
    private var youTubeLiveChat: YouTubeLiveChat?
    private var afreecaTvChat: AfreecaTvChat?
    private var openStreamingPlatformChat: OpenStreamingPlatformChat!
    private var obsWebSocket: ObsWebSocket?
    private var chatPostId = 0
    @Published var chatPosts: Deque<ChatPost> = []
    private var pausedChatPosts: Deque<ChatPost> = []
    @Published var pausedChatPostsCount: Int = 0
    private var newChatPosts: Deque<ChatPost> = []
    private var numberOfChatPostsPerTick = 0
    private var chatPostsRatePerSecond = 0.0
    private var chatPostsRatePerMinute = 0.0
    private var numberOfChatPostsPerMinute = 0
    @Published var chatPostsRate = String(localized: "0.0/min")
    @Published var chatPostsTotal: Int = 0
    private var watchChatPosts: Deque<WatchProtocolChatMessage> = []
    private var nextWatchChatPostId = 1
    private var chatSpeedTicks = 0
    @Published var numberOfViewers = noValue
    @Published var batteryLevel = Double(UIDevice.current.batteryLevel)
    @Published var batteryState: UIDevice.BatteryState = .full
    @Published var speedAndTotal = noValue
    @Published var thermalState = ProcessInfo.processInfo.thermalState
    let streamPreviewView = PreviewView(frame: .zero)
    let cameraPreviewView = CameraPreviewUiView()
    @Published var remoteControlPreview: UIImage?
    @Published var showCameraPreview = false
    private var textEffects: [UUID: TextEffect] = [:]
    private var imageEffects: [UUID: ImageEffect] = [:]
    private var browserEffects: [UUID: BrowserEffect] = [:]
    private var lutEffects: [UUID: LutEffect] = [:]
    private var drawOnStreamEffect = DrawOnStreamEffect()
    private var lutEffect = LutEffect()
    @Published var browsers: [Browser] = []
    @Published var sceneIndex = 0
    @Published var isTorchOn = false
    @Published var isFrontCameraSelected = false
    private var isMuteOn = false
    var log: Deque<LogEntry> = []
    var remoteControlAssistantLog: Deque<LogEntry> = []
    var imageStorage = ImageStorage()
    @Published var buttonPairs: [ButtonPair] = []
    private var reconnectTimer: Timer?
    private var logId = 1
    @Published var showingToast = false
    @Published var toast = AlertToast(type: .regular, title: "") {
        didSet {
            showingToast.toggle()
        }
    }

    @Published var showingBitrate = false
    @Published var showingMic = false
    @Published var showingRecordings = false
    @Published var showingCamera = false
    @Published var showingCameraBias = false
    @Published var showingCameraWhiteBalance = false
    @Published var showingCameraIso = false
    @Published var showingCameraFocus = false
    @Published var showingStreamSwitcher = false
    @Published var showingGrid = false
    @Published var showingObs = false
    @Published var showingRemoteControl = false
    @Published var obsScenes: [String] = []
    @Published var obsAudioVolume: String = noValue
    @Published var obsAudioDelay: Int = 0
    private var obsAudioVolumeLatest: String = ""
    @Published var obsCurrentScenePicker: String = ""
    @Published var obsCurrentScene: String = ""
    @Published var currentStreamId = UUID()
    @Published var obsStreaming = false
    @Published var obsStreamingState: ObsOutputState = .stopped
    @Published var obsRecordingState: ObsOutputState = .stopped
    @Published var obsFixOngoing = false
    @Published var obsScreenshot: CGImage?
    private var obsSourceFetchScreenshot = false
    private var obsSourceScreenshotIsFetching = false
    var obsRecording = false
    @Published var iconImage: String = plainIcon.id
    @Published var backZoomPresetId = UUID()
    @Published var frontZoomPresetId = UUID()
    @Published var zoomX: Float = 1.0
    @Published var hasZoom = true
    private var zoomXPinch: Float = 1.0
    private var backZoomX: Float = 0.5
    private var frontZoomX: Float = 1.0
    var cameraPosition: AVCaptureDevice.Position?
    private let motionManager = CMMotionManager()
    var database: Database {
        settings.database
    }

    @Published var showDrawOnStream = false
    @Published var showFace = false
    @Published var showFaceBeauty = false
    @Published var showFaceBeautyShape = false
    @Published var showFaceBeautySmooth = false
    @Published var showLocalOverlays = true
    @Published var showBrowser = false
    @Published var drawOnStreamLines: [DrawOnStreamLine] = []
    @Published var drawOnStreamSelectedColor: Color = .pink
    @Published var drawOnStreamSelectedWidth: CGFloat = 4
    var drawOnStreamSize: CGSize = .zero
    @Published var webBrowserUrl: String = ""
    private var webBrowser: WKWebView?

    @Published var isPresentingWizard = false
    @Published var isPresentingSetupWizard = false
    var wizardPlatform: WizardPlatform = .custom
    var wizardNetworkSetup: WizardNetworkSetup = .none
    var wizardCustomProtocol: WizardCustomProtocol = .none
    @Published var wizardName = ""
    @Published var wizardTwitchChannelName = ""
    @Published var wizardTwitchChannelId = ""
    @Published var wizardKickChannelName = ""
    @Published var wizardYouTubeVideoId = ""
    @Published var wizardAfreecaTvChannelName = ""
    @Published var wizardAfreecsTvCStreamId = ""
    @Published var wizardObsAddress = ""
    @Published var wizardObsPort = ""
    @Published var wizardObsRemoteControlEnabled = false
    @Published var wizardObsRemoteControlUrl = ""
    @Published var wizardObsRemoteControlPassword = ""
    @Published var wizardObsRemoteControlSourceName = ""
    @Published var wizardDirectIngest = ""
    @Published var wizardDirectStreamKey = ""
    @Published var wizardChatBttv = true
    @Published var wizardChatFfz = true
    @Published var wizardChatSeventv = true
    @Published var wizardBelaboxUrl = ""
    @Published var wizardCustomSrtUrl = ""
    @Published var wizardCustomSrtStreamId = ""
    @Published var wizardCustomRtmpUrl = ""
    @Published var wizardCustomRtmpStreamKey = ""
    @Published var wizardCustomRistUrl = ""

    let chatTextToSpeech = ChatTextToSpeech()

    private var lastAttachCompletedTime: ContinuousClock.Instant?

    @Published var remoteControlGeneral: RemoteControlStatusGeneral?
    @Published var remoteControlTopLeft: RemoteControlStatusTopLeft?
    @Published var remoteControlTopRight: RemoteControlStatusTopRight?
    @Published var remoteControlSettings: RemoteControlSettings?
    var remoteControlState = RemoteControlState()
    @Published var remoteControlScene = UUID()
    @Published var remoteControlMic = ""
    @Published var remoteControlBitrate = UUID()
    @Published var remoteControlZoom = ""

    private var remoteControlStreamer: RemoteControlStreamer?
    private var remoteControlAssistant: RemoteControlAssistant?
    @Published var remoteControlAssistantShowPreview = true

    private var currentWiFiSsid: String?

    var cameraDevice: AVCaptureDevice?
    var cameraZoomLevelToXScale: Float = 1.0
    var cameraZoomXMinimum: Float = 1.0
    var cameraZoomXMaximum: Float = 1.0
    @Published var debugLines: [String] = []
    @Published var streamingHistory = StreamingHistory()
    private var streamingHistoryStream: StreamingHistoryStream?

    var backCameras: [Camera] = []
    var frontCameras: [Camera] = []
    var externalCameras: [Camera] = []

    var recordingsStorage = RecordingsStorage()
    private var latestLowBitrateTime = ContinuousClock.now

    private var rtmpServer: RtmpServer?
    @Published var serversSpeedAndTotal = noValue

    private var srtlaServer: SrtlaServer?

    private var gameControllers: [GCController?] = []
    @Published var gameControllersTotal = noValue

    @Published var location = noValue
    @Published var showLoadSettingsFailed = false

    @Published var remoteControlStatus = noValue

    private let sampleBufferReceiver = SampleBufferReceiver()

    override init() {
        super.init()
        showLoadSettingsFailed = !settings.load()
        streamingHistory.load()
        recordingsStorage.load()
    }

    var stream: SettingsStream {
        for stream in database.streams where stream.enabled {
            return stream
        }
        return fallbackStream
    }

    var enabledScenes: [SettingsScene] {
        database.scenes.filter { scene in scene.enabled }
    }

    @Published var myIcons: [Icon] = []
    @Published var iconsInStore: [Icon] = []
    private var appStoreUpdateListenerTask: Task<Void, Error>?
    private var products: [String: Product] = [:]
    private var streamTotalBytes: UInt64 = 0
    private var streamTotalChatMessages: Int = 0
    var ipMonitor = IPMonitor(ipType: .ipv4)
    @Published var ipStatuses: [IPMonitor.Status] = []
    private var faceEffect = FaceEffect(fps: 30)
    private var movieEffect = MovieEffect()
    private var grayScaleEffect = GrayScaleEffect()
    private var sepiaEffect = SepiaEffect()
    private var tripleEffect = TripleEffect()
    private var pixellateEffect = PixellateEffect()
    private var locationManager = Location()
    private var realtimeIrl: RealtimeIrl?
    private var failedVideoEffect: String?
    var supportsAppleLog: Bool = false

    func updateAdaptiveBitrateSrtIfEnabled(stream: SettingsStream) {
        switch stream.srt.adaptiveBitrate!.algorithm {
        case .fastIrl:
            var settings = adaptiveBitrateFastSettings
            settings.packetsInFlight = Int64(stream.srt.adaptiveBitrate!.fastIrlSettings!.packetsInFlight)
            settings
                .minimumBitrate = Int64(stream.srt.adaptiveBitrate!.fastIrlSettings!.minimumBitrate! * 1000)
            media.setAdaptiveBitrateSettings(settings: settings)
        case .slowIrl:
            media.setAdaptiveBitrateSettings(settings: adaptiveBitrateSlowSettings)
        case .customIrl:
            let customSettings = stream.srt.adaptiveBitrate!.customSettings
            media.setAdaptiveBitrateSettings(settings: AdaptiveBitrateSettings(
                packetsInFlight: Int64(customSettings.packetsInFlight),
                rttDiffHighFactor: Double(customSettings.rttDiffHighDecreaseFactor),
                rttDiffHighAllowedSpike: Double(customSettings.rttDiffHighAllowedSpike),
                rttDiffHighMinDecrease: Int64(customSettings.rttDiffHighMinimumDecrease * 1000),
                pifDiffIncreaseFactor: Int64(customSettings.pifDiffIncreaseFactor * 1000),
                minimumBitrate: Int64(customSettings.minimumBitrate! * 1000)
            ))
        }
    }

    func updateAdaptiveBitrateRtmpIfEnabled() {
        var settings = adaptiveBitrateFastSettings
        settings.rttDiffHighAllowedSpike = 500
        media.setAdaptiveBitrateSettings(settings: settings)
    }

    func updateAdaptiveBitrateRistIfEnabled() {
        let settings = adaptiveBitrateRistFastSettings
        media.setAdaptiveBitrateSettings(settings: settings)
    }

    @MainActor
    private func getProductsFromAppStore() async {
        do {
            let products = try await Product.products(for: iconsProductIds)
            for product in products {
                self.products[product.id] = product
            }
            logger.info("cosmetics: Got \(products.count) product(s) from App Store")
        } catch {
            logger.error("cosmetics: Failed to get products from App Store: \(error)")
        }
    }

    private func listenForAppStoreTransactions() -> Task<Void, Error> {
        return Task.detached {
            for await result in Transaction.updates {
                guard let transaction = self.checkVerified(result: result) else {
                    logger.info("cosmetics: Updated transaction failed verification")
                    continue
                }
                await self.updateProductFromAppStore()
                await transaction.finish()
            }
        }
    }

    private func checkVerified(result: VerificationResult<StoreKit.Transaction>)
        -> StoreKit.Transaction?
    {
        switch result {
        case .unverified:
            return nil
        case let .verified(safe):
            return safe
        }
    }

    @MainActor
    func updateProductFromAppStore() async {
        logger.info("cosmetics: Update my products from App Store")
        let myProductIds = await getMyProductIds()
        updateIcons(myProductIds: myProductIds)
    }

    private func getMyProductIds() async -> [String] {
        var myProductIds: [String] = []
        for await result in Transaction.currentEntitlements {
            guard let transaction = checkVerified(result: result) else {
                logger.info("cosmetics: Verification failed for my product")
                continue
            }
            myProductIds.append(transaction.productID)
        }
        return myProductIds
    }

    private func updateIcons(myProductIds: [String]) {
        var myIcons = globalMyIcons
        var iconsInStore: [Icon] = []
        for productId in iconsProductIds {
            guard let product = products[productId] else {
                logger.info("cosmetics: Icon product \(productId) not found")
                continue
            }
            if myProductIds.contains(productId) {
                myIcons.append(Icon(
                    name: product.displayName,
                    id: product.id,
                    price: product.displayPrice
                ))
            } else {
                iconsInStore.append(Icon(
                    name: product.displayName,
                    id: product.id,
                    price: product.displayPrice
                ))
            }
        }
        self.myIcons = myIcons
        self.iconsInStore = iconsInStore
    }

    private func findProduct(id: String) -> Product? {
        return products[id]
    }

    func purchaseProduct(id: String) async throws {
        guard let product = findProduct(id: id) else {
            throw "Product not found"
        }
        let result = try await product.purchase()

        switch result {
        case let .success(result):
            logger.info("cosmetics: Purchase successful")
            guard let transaction = checkVerified(result: result) else {
                throw "Purchase failed verification"
            }
            await updateProductFromAppStore()
            await transaction.finish()
        case .userCancelled, .pending:
            logger.info("cosmetics: Purchase not done yet")
        default:
            logger.warning("cosmetics: What happend when buying? \(result)")
        }
    }

    func setAllowVideoRangePixelFormat() {
        allowVideoRangePixelFormat = database.debug!.allowVideoRangePixelFormat!
    }

    func setBlurSceneSwitch() {
        ioVideoBlurSceneSwitch = database.debug!.blurSceneSwitch!
    }

    func makeToast(title: String, subTitle: String? = nil) {
        toast = AlertToast(type: .regular, title: title, subTitle: subTitle)
        showingToast = true
        logger.debug("toast: Info: \(title): \(subTitle ?? "-")")
    }

    func makeWarningToast(title: String, subTitle: String? = nil, vibrate: Bool = false) {
        toast = AlertToast(type: .regular, title: formatWarning(title), subTitle: subTitle)
        showingToast = true
        logger.debug("toast: Warning: \(title): \(subTitle ?? "-")")
        if vibrate {
            UIDevice.vibrate()
        }
    }

    func makeErrorToast(title: String, font: Font? = nil, subTitle: String? = nil, vibrate: Bool = false) {
        toast = AlertToast(
            type: .regular,
            title: title,
            subTitle: subTitle,
            style: .style(titleColor: .red, titleFont: font)
        )
        showingToast = true
        logger.debug("toast: Error: \(title): \(subTitle ?? "-")")
        if vibrate {
            UIDevice.vibrate()
        }
    }

    func scrollQuickButtonsToBottom() {
        scrollQuickButtons += 1
    }

    func updateButtonStates() {
        let states = database.globalButtons!.filter { button in
            button.enabled!
        }.map { button in
            ButtonState(isOn: button.isOn, button: button)
        }
        var pairs: [ButtonPair] = []
        for index in stride(from: 0, to: states.count, by: 2) {
            if states.count - index > 1 {
                pairs.append(ButtonPair(
                    id: UUID(),
                    first: states[index],
                    second: states[index + 1]
                ))
            } else {
                pairs.append(ButtonPair(id: UUID(), first: states[index]))
            }
        }
        buttonPairs = pairs.reversed()
    }

    func debugLog(message: String) {
        DispatchQueue.main.async {
            if self.log.count > self.database.debug!.maximumLogLines! {
                self.log.removeFirst()
            }
            self.log.append(LogEntry(id: self.logId, message: message))
            self.logId += 1
            self.remoteControlStreamer?.log(entry: message)
        }
    }

    func clearLog() {
        log = []
    }

    func formatLog(log: Deque<LogEntry>) -> String {
        var data = "Version: \(appVersion())\n"
        data += "Debug: \(logger.debugEnabled)\n\n"
        data += log.map { e in e.message }.joined(separator: "\n")
        return data
    }

    func setAllowHapticsAndSystemSoundsDuringRecording() {
        do {
            try AVAudioSession.sharedInstance()
                .setAllowHapticsAndSystemSoundsDuringRecording(database.vibrate!)
        } catch {}
    }

    func isObsConnected() -> Bool {
        return obsWebSocket?.isConnected() ?? false
    }

    func obsConnectionErrorMessage() -> String {
        return obsWebSocket?.connectionErrorMessage ?? ""
    }

    func listObsScenes() {
        obsWebSocket?.getSceneList(onSuccess: { list in
            DispatchQueue.main.async {
                self.obsCurrentScenePicker = list.current
                self.obsCurrentScene = list.current
                self.obsScenes = list.scenes
            }
        }, onError: { _ in
        })
    }

    func setObsScene(name: String) {
        obsWebSocket?.setCurrentProgramScene(name: name, onSuccess: {
            DispatchQueue.main.async {
                self.obsCurrentScene = name
            }
        }, onError: { message in
            DispatchQueue.main.async {
                self.makeErrorToast(title: String(localized: "Failed to set OBS scene to \(name)"),
                                    subTitle: message)
            }
        })
    }

    private func updateObsStatus() {
        guard isObsConnected() else {
            obsAudioVolumeLatest = noValue
            return
        }
        obsWebSocket?.getStreamStatus(onSuccess: { state in
            self.handleObsStreamStatusChanged(active: state.active, state: state.state)
        }, onError: { _ in
            self.handleObsStreamStatusChanged(active: false)
        })
        obsWebSocket?.getRecordStatus(onSuccess: { status in
            self.handleObsRecordStatusChanged(active: status.active)
        }, onError: { _ in
            self.handleObsRecordStatusChanged(active: false)
        })
        listObsScenes()
    }

    func setup() {
        setAllowVideoRangePixelFormat()
        setBlurSceneSwitch()
        supportsAppleLog = hasAppleLog()
        ioVideoUnitIgnoreFramesAfterAttachSeconds = Double(database.debug!.cameraSwitchRemoveBlackish!)
        let WebPCoder = SDImageWebPCoder.shared
        SDImageCodersManager.shared.addCoder(WebPCoder)
        UIDevice.current.isBatteryMonitoringEnabled = true
        logger.handler = debugLog(message:)
        logger.debugEnabled = database.debug!.logLevel == .debug
        updateCameraLists()
        updateBatteryLevel()
        media.onSrtConnected = handleSrtConnected
        media.onSrtDisconnected = handleSrtDisconnected
        media.onRtmpConnected = handleRtmpConnected
        media.onRtmpDisconnected = handleRtmpDisconnected
        media.onRistConnected = handleRistConnected
        media.onRistDisconnected = handleRistDisconnected
        media.onAudioMuteChange = updateAudioLevel
        media.onLowFpsImage = handleLowFpsImage
        media.onFindVideoFormatError = handleFindVideoFormatError
        setPixelFormat()
        setMetalPetalFilters()
        setHigherDataRateLimit()
        setUseAudioForTimestamps()
        setupAudioSession()
        if let cameraDevice = preferredCamera(position: .back) {
            (cameraZoomXMinimum, cameraZoomXMaximum) = cameraDevice
                .getUIZoomRange(hasUltraWideCamera: hasUltraWideBackCamera())
            if let preset = backZoomPresets().first {
                backZoomPresetId = preset.id
                backZoomX = preset.x!
            } else {
                backZoomX = cameraZoomXMinimum
            }
            zoomX = backZoomX
        }
        frontZoomPresetId = database.zoom.front[0].id
        streamPreviewView.videoGravity = .resizeAspect
        updateDigitalClock(now: Date())
        twitchChat = TwitchChatMoblin(model: self)
        reloadStream()
        resetSelectedScene()
        setMic()
        setupPeriodicTimers()
        setupThermalState()
        updateButtonStates()
        scrollQuickButtonsToBottom()
        removeUnusedImages()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(orientationDidChange),
            name: UIDevice.orientationDidChangeNotification,
            object: nil
        )
        iconImage = database.iconImage
        Task {
            appStoreUpdateListenerTask = listenForAppStoreTransactions()
            await getProductsFromAppStore()
            await updateProductFromAppStore()
            DispatchQueue.main.async {
                self.updateIconImageFromDatabase()
            }
        }
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(
                                                   handleAudioRouteChange
                                               ),
                                               name: AVAudioSession
                                                   .routeChangeNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(
                                                   handleDidEnterBackgroundNotification
                                               ),
                                               name: UIApplication.didEnterBackgroundNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(
                                                   handleWillEnterForegroundNotification
                                               ),
                                               name: UIApplication
                                                   .willEnterForegroundNotification,
                                               object: nil)
        updateOrientation()
        reloadRtmpServer()
        reloadSrtlaServer()
        ipMonitor.pathUpdateHandler = handleIpStatusUpdate
        ipMonitor.start()
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(
                                                   handleBatteryStateDidChangeNotification
                                               ),
                                               name: UIDevice.batteryStateDidChangeNotification,
                                               object: nil)
        updateBatteryState()
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleGameControllerDidConnect),
                                               name: NSNotification.Name.GCControllerDidConnect,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleGameControllerDidDisconnect),
                                               name: NSNotification.Name.GCControllerDidDisconnect,
                                               object: nil)
        GCController.startWirelessControllerDiscovery {}
        reloadLocation()
        currentStreamId = stream.id
        lutUpdated()
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleCaptureDeviceWasConnected),
                                               name: NSNotification.Name.AVCaptureDeviceWasConnected,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleCaptureDeviceWasDisconnected),
                                               name: NSNotification.Name.AVCaptureDeviceWasDisconnected,
                                               object: nil)

        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            session.activate()
        } else {
            logger.info("watch: Not supported")
        }
        chatTextToSpeech.setRate(rate: database.chat.textToSpeechRate!)
        chatTextToSpeech.setVolume(volume: database.chat.textToSpeechSayVolume!)
        chatTextToSpeech.setVoices(voices: database.chat.textToSpeechLanguageVoices!)
        chatTextToSpeech.setSayUsername(value: database.chat.textToSpeechSayUsername!)
        chatTextToSpeech
            .setDetectLanguagePerMessage(value: database.chat.textToSpeechDetectLanguagePerMessage!)
        chatTextToSpeech.setFilter(value: database.chat.textToSpeechFilter!)
        AppDelegate.orientationLock = .landscape
        updateOrientationLock()
        updateFaceFilterSettings()
        setupSampleBufferReceiver()
    }

    func setMetalPetalFilters() {
        ioVideoUnitMetalPetal = database.debug!.metalPetalFilters!
    }

    func setHigherDataRateLimit() {
        videoCodecHigherDataRateLimit = database.debug!.higherDataRateLimit!
    }

    func setUseAudioForTimestamps() {
        if database.debug!.useAudioForTimestamps! {
            mpegTsWriterProgramClockReferencePacketId = MpegTsWriter.audioPacketId
        } else {
            mpegTsWriterProgramClockReferencePacketId = MpegTsWriter.videoPacketId
        }
    }

    private func setupSampleBufferReceiver() {
        sampleBufferReceiver.delegate = self
        sampleBufferReceiver.start(appGroup: moblinAppGroup)
    }

    func updateFaceFilterSettings() {
        let settings = database.debug!.beautyFilterSettings!
        faceEffect.safeSettings.mutate { $0 = FaceEffectSettings(
            showCrop: database.debug!.beautyFilter!,
            showBlur: settings.showBlur,
            showMouth: settings.showMoblin,
            showBeauty: settings.showBeauty!,
            shapeRadius: settings.shapeRadius!,
            shapeAmount: settings.shapeScale!,
            shapeOffset: settings.shapeOffset!,
            smoothAmount: settings.smoothAmount!,
            smoothRadius: settings.smoothRadius!
        ) }
    }

    func setPixelFormat() {
        for (format, type) in zip(pixelFormats, pixelFormatTypes) where
            database.debug!.pixelFormat == format
        {
            logger.info("Setting pixel format \(format)")
            pixelFormatType = type
        }
    }

    private func handleIpStatusUpdate(statuses: [IPMonitor.Status]) {
        ipStatuses = statuses
        for status in statuses where status.interfaceType == .wiredEthernet {
            for stream in database.streams
                where !stream.srt.connectionPriorities!.priorities.contains(where: { priority in
                    priority.name == status.name
                })
            {
                stream.srt.connectionPriorities!.priorities
                    .append(SettingsStreamSrtConnectionPriority(name: status.name))
                store()
            }
            if !database.networkInterfaceNames!.contains(where: { interface in
                interface.interfaceName == status.name
            }) {
                let interface = SettingsNetworkInterfaceName()
                interface.interfaceName = status.name
                interface.name = status.name
                database.networkInterfaceNames!.append(interface)
                store()
            }
        }
    }

    private func handleGameControllerButtonZoom(pressed: Bool, x: Float) {
        if pressed {
            if let x = setCameraZoomX(x: x, rate: database.zoom.speed!) {
                setZoomX(x: x)
            }
        } else {
            if let x = stopCameraZoom() {
                setZoomX(x: x)
            }
        }
    }

    private func handleGameControllerButton(
        _ gameController: GCController,
        _ button: GCControllerButtonInput,
        _: Float,
        _ pressed: Bool
    ) {
        guard let gameControllerIndex = gameControllers.firstIndex(of: gameController) else {
            return
        }
        guard gameControllerIndex < database.gameControllers!.count else {
            return
        }
        guard let name = button.sfSymbolsName else {
            return
        }
        let button = database.gameControllers![gameControllerIndex].buttons.first(where: { button in
            button.name == name
        })
        guard let button else {
            return
        }
        switch button.function {
        case .unused:
            break
        case .record:
            if !pressed {
                toggleRecording()
                updateButtonStates()
            }
        case .stream:
            if !pressed {
                toggleStream()
                updateButtonStates()
            }
        case .zoomIn:
            handleGameControllerButtonZoom(pressed: pressed, x: Float.infinity)
        case .zoomOut:
            handleGameControllerButtonZoom(pressed: pressed, x: 0)
        case .torch:
            if !pressed {
                toggleTorch()
                toggleGlobalButton(type: .torch)
                updateButtonStates()
            }
        case .mute:
            if !pressed {
                toggleMute()
                toggleGlobalButton(type: .mute)
                updateButtonStates()
            }
        case .blackScreen:
            if !pressed {
                toggleBlackScreen()
                updateButtonStates()
            }
        case .chat:
            if !pressed {
                showChatMessages.toggle()
                toggleGlobalButton(type: .chat)
                sceneUpdated(store: false)
                updateButtonStates()
            }
        case .interactiveChat:
            break
        case .scene:
            if !pressed {
                selectScene(id: button.sceneId)
            }
        }
    }

    private func updateCameraLists() {
        if ProcessInfo().isiOSAppOnMac {
            externalCameras = []
            backCameras = listCameras(position: .back)
            frontCameras = listCameras(position: .front)
        } else {
            externalCameras = listExternalCameras()
            backCameras = listCameras(position: .back)
            frontCameras = listCameras(position: .front)
        }
    }

    @objc func handleCaptureDeviceWasConnected(_: Notification) {
        logger.info("Capture device connected")
        updateCameraLists()
    }

    @objc func handleCaptureDeviceWasDisconnected(_: Notification) {
        logger.info("Capture device disconnected")
        updateCameraLists()
    }

    private func numberOfGameControllers() -> Int {
        return gameControllers.filter { gameController in
            gameController != nil
        }.count
    }

    func isGameControllerConnected() -> Bool {
        return numberOfGameControllers() > 0
    }

    private func updateGameControllers() {
        gameControllersTotal = String(numberOfGameControllers())
    }

    private func gameControllerNumber(gameController: GCController) -> Int? {
        if let gameControllerIndex = gameControllers.firstIndex(of: gameController) {
            return gameControllerIndex + 1
        }
        return nil
    }

    @objc func handleGameControllerDidConnect(_ notification: Notification) {
        guard let gameController = notification.object as? GCController else {
            return
        }
        guard let gamepad = gameController.extendedGamepad else {
            return
        }
        gamepad.dpad.left.pressedChangedHandler = { button, value, pressed in
            self.handleGameControllerButton(gameController, button, value, pressed)
        }
        gamepad.dpad.right.pressedChangedHandler = { button, value, pressed in
            self.handleGameControllerButton(gameController, button, value, pressed)
        }
        gamepad.dpad.up.pressedChangedHandler = { button, value, pressed in
            self.handleGameControllerButton(gameController, button, value, pressed)
        }
        gamepad.dpad.down.pressedChangedHandler = { button, value, pressed in
            self.handleGameControllerButton(gameController, button, value, pressed)
        }
        gamepad.buttonA.pressedChangedHandler = { button, value, pressed in
            self.handleGameControllerButton(gameController, button, value, pressed)
        }
        gamepad.buttonB.pressedChangedHandler = { button, value, pressed in
            self.handleGameControllerButton(gameController, button, value, pressed)
        }
        gamepad.buttonX.pressedChangedHandler = { button, value, pressed in
            self.handleGameControllerButton(gameController, button, value, pressed)
        }
        gamepad.buttonY.pressedChangedHandler = { button, value, pressed in
            self.handleGameControllerButton(gameController, button, value, pressed)
        }
        gamepad.buttonMenu.pressedChangedHandler = { button, value, pressed in
            self.handleGameControllerButton(gameController, button, value, pressed)
        }
        gamepad.leftShoulder.pressedChangedHandler = { button, value, pressed in
            self.handleGameControllerButton(gameController, button, value, pressed)
        }
        gamepad.rightShoulder.pressedChangedHandler = { button, value, pressed in
            self.handleGameControllerButton(gameController, button, value, pressed)
        }
        gamepad.leftTrigger.pressedChangedHandler = { button, value, pressed in
            self.handleGameControllerButton(gameController, button, value, pressed)
        }
        gamepad.rightTrigger.pressedChangedHandler = { button, value, pressed in
            self.handleGameControllerButton(gameController, button, value, pressed)
        }
        if let index = gameControllers.firstIndex(of: nil) {
            gameControllers[index] = gameController
        } else {
            gameControllers.append(gameController)
        }
        if let number = gameControllerNumber(gameController: gameController) {
            makeToast(title: "Game controller \(number) connected")
        }
        updateGameControllers()
    }

    @objc func handleGameControllerDidDisconnect(notification: Notification) {
        guard let gameController = notification.object as? GCController else {
            return
        }
        if let number = gameControllerNumber(gameController: gameController) {
            makeToast(title: "Game controller \(number) disconnected")
        }
        if let index = gameControllers.firstIndex(of: gameController) {
            gameControllers[index] = nil
        }
        updateGameControllers()
    }

    @objc func handleDidEnterBackgroundNotification() {
        if isRecording {
            suspendRecording()
        }
        if !shouldStreamInBackground() {
            stopStream()
            stopRtmpServer()
            teardownAudioSession()
            chatTextToSpeech.reset(running: false)
        }
    }

    @objc func handleWillEnterForegroundNotification() {
        if !shouldStreamInBackground() {
            setupAudioSession()
            media.attachAudio(device: AVCaptureDevice.default(for: .audio))
            reloadConnections()
            reloadRtmpServer()
            chatTextToSpeech.reset(running: true)
        }
        if isRecording {
            resumeRecording()
        }
    }

    private func shouldStreamInBackground() -> Bool {
        return isLive && stream.backgroundStreaming!
    }

    @objc func handleBatteryStateDidChangeNotification() {
        updateBatteryState()
    }

    private func stopRtmpServer() {
        rtmpServer?.stop()
        rtmpServer = nil
        stopAllRtmpStreams()
    }

    func reloadRtmpServer() {
        stopRtmpServer()
        if database.rtmpServer!.enabled {
            rtmpServer = RtmpServer(settings: database.rtmpServer!.clone(),
                                    onPublishStart: handleRtmpServerPublishStart,
                                    onPublishStop: handleRtmpServerPublishStop,
                                    onFrame: handleRtmpServerFrame,
                                    onAudioBuffer: handleRtmpServerAudioBuffer)
            rtmpServer!.start()
        }
    }

    private func stopSrtlaServer() {
        srtlaServer?.stop()
        srtlaServer = nil
    }

    func reloadSrtlaServer() {
        stopSrtlaServer()
        if database.debug!.srtlaServer! && database.srtlaServer!.enabled {
            srtlaServer = SrtlaServer(settings: database.srtlaServer!)
            srtlaServer!.delegate = self
            srtlaServer!.start()
        }
    }

    func srtlaServerEnabled() -> Bool {
        return srtlaServer != nil
    }

    private func srtlaCameras() -> [String] {
        return database.srtlaServer!.streams.map { stream in
            stream.camera()
        }
    }

    func getSrtlaStream(id: UUID) -> SettingsSrtlaServerStream? {
        return database.srtlaServer!.streams.first { stream in
            stream.id == id
        }
    }

    func getSrtlaStream(camera: String) -> SettingsSrtlaServerStream? {
        return database.srtlaServer!.streams.first { stream in
            camera == stream.camera()
        }
    }

    func getSrtlaStream(streamId: String) -> SettingsSrtlaServerStream? {
        return database.srtlaServer!.streams.first { stream in
            stream.streamId == streamId
        }
    }

    func isSrtlaStreamConnected(streamId: String) -> Bool {
        return srtlaServer?.isStreamConnected(streamId: streamId) ?? false
    }

    func reloadRtmpStreams() {
        for rtmpCamera in rtmpCameras() {
            guard let stream = getRtmpStream(camera: rtmpCamera) else {
                continue
            }
            if isRtmpStreamConnected(streamKey: stream.streamKey) {
                let micId = "\(stream.id.uuidString) 0"
                let isLastMic = (currentMic.id == micId)
                handleRtmpServerPublishStop(streamKey: stream.streamKey)
                handleRtmpServerPublishStart(streamKey: stream.streamKey)
                if isLastMic {
                    setMic(id: micId) {}
                }
            }
        }
    }

    func handleRtmpServerPublishStart(streamKey: String) {
        DispatchQueue.main.async {
            let camera = self.getRtmpStream(streamKey: streamKey)?.camera() ?? rtmpCamera(name: "Unknown")
            self.makeToast(title: "\(camera) connected")
            guard let stream = self.getRtmpStream(streamKey: streamKey) else {
                return
            }
            let latency = Double(stream.latency!) / 1000
            self.media.addRtmpCamera(cameraId: stream.id, latency: latency)
            self.media.addRtmpAudio(cameraId: stream.id, latency: latency)
        }
    }

    func handleRtmpServerPublishStop(streamKey: String) {
        DispatchQueue.main.async {
            let camera = self.getRtmpStream(streamKey: streamKey)?.camera() ?? rtmpCamera(name: "Unknown")
            self.makeToast(title: "\(camera) disconnected")
            guard let stream = self.getRtmpStream(streamKey: streamKey) else {
                return
            }
            self.media.removeRtmpCamera(cameraId: stream.id)
            self.media.removeRtmpAudio(cameraId: stream.id)
            if self.currentMic.inputUid == stream.id.uuidString {
                self.setMicFromSettings()
            }
        }
    }

    func handleRtmpServerFrame(streamKey: String, sampleBuffer: CMSampleBuffer) {
        guard let cameraId = getRtmpStream(streamKey: streamKey)?.id else {
            return
        }
        media.addRtmpSampleBuffer(cameraId: cameraId, sampleBuffer: sampleBuffer)
    }

    func handleRtmpServerAudioBuffer(streamKey: String, sampleBuffer: CMSampleBuffer) {
        guard let cameraId = getRtmpStream(streamKey: streamKey)?.id else {
            return
        }
        media.addRtmpAudioSampleBuffer(cameraId: cameraId, sampleBuffer: sampleBuffer)
    }

    private func listCameras(position: AVCaptureDevice.Position) -> [Camera] {
        var deviceTypes: [AVCaptureDevice.DeviceType] = [
            .builtInTripleCamera,
            .builtInDualCamera,
            .builtInDualWideCamera,
            .builtInUltraWideCamera,
            .builtInWideAngleCamera,
            .builtInTelephotoCamera,
        ]
        if #available(iOS 17.0, *) {
            deviceTypes.append(.external)
        }
        let deviceDiscovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .video,
            position: position
        )
        return deviceDiscovery.devices.map { device in
            Camera(id: device.uniqueID, name: cameraName(device: device))
        }
    }

    func isSceneActive(scene: SettingsScene) -> Bool {
        switch scene.cameraPosition {
        case .rtmp:
            if let stream = getRtmpStream(id: scene.rtmpCameraId!) {
                return isRtmpStreamConnected(streamKey: stream.streamKey)
            } else {
                return false
            }
        case .external:
            return isExternalCameraConnected(id: scene.externalCameraId!)
        default:
            return true
        }
    }

    private func isExternalCameraConnected(id: String) -> Bool {
        externalCameras.first { camera in
            camera.id == id
        } != nil
    }

    private func listExternalCameras() -> [Camera] {
        var deviceTypes: [AVCaptureDevice.DeviceType] = []
        if #available(iOS 17.0, *) {
            deviceTypes.append(.external)
        }
        let deviceDiscovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .video,
            position: .unspecified
        )
        return deviceDiscovery.devices.map { device in
            Camera(id: device.uniqueID, name: cameraName(device: device))
        }
    }

    deinit {
        appStoreUpdateListenerTask?.cancel()
    }

    func updateOrientation() {
        if stream.portrait! {
            streamPreviewView.videoOrientation = .landscapeRight
        } else {
            switch UIDevice.current.orientation {
            case .landscapeLeft:
                streamPreviewView.videoOrientation = .landscapeRight
            case .landscapeRight:
                streamPreviewView.videoOrientation = .landscapeLeft
            default:
                break
            }
        }
        updateCameraPreviewRotation()
    }

    @objc private func orientationDidChange(animated _: Bool) {
        updateOrientation()
    }

    private func isInMyIcons(id: String) -> Bool {
        return myIcons.contains(where: { icon in
            icon.id == id
        })
    }

    func updateIconImageFromDatabase() {
        if !isInMyIcons(id: database.iconImage) {
            logger.warning("Database icon image \(database.iconImage) is not mine")
            database.iconImage = plainIcon.id
            store()
        }
        iconImage = database.iconImage
    }

    private func handleSettingsUrlsDefaultStreams(settings: MoblinSettingsUrl) {
        var newSelectedStream: SettingsStream?
        for stream in settings.streams ?? [] {
            let newStream = SettingsStream(name: stream.name)
            newStream.url = stream.url
            if stream.selected == true {
                newSelectedStream = newStream
            }
            if let video = stream.video {
                if let codec = video.codec {
                    newStream.codec = codec
                }
            }
            if let srt = stream.srt {
                if let latency = srt.latency {
                    newStream.srt.latency = latency
                }
                if let adaptiveBitrateEnabled = srt.adaptiveBitrateEnabled {
                    newStream.srt.adaptiveBitrateEnabled = adaptiveBitrateEnabled
                }
            }
            if let obs = stream.obs {
                newStream.obsWebSocketUrl = obs.webSocketUrl
                newStream.obsWebSocketPassword = obs.webSocketPassword
            }
            database.streams.append(newStream)
        }
        if let newSelectedStream, !isLive, !isRecording {
            setCurrentStream(stream: newSelectedStream)
            reloadStream()
            sceneUpdated(store: false)
            resetSelectedScene(changeScene: false)
        }
    }

    private func handleSettingsUrlsDefaultQuickButtons(settings: MoblinSettingsUrl) {
        if let quickButtons = settings.quickButtons {
            if let twoColumns = quickButtons.twoColumns {
                database.quickButtons!.twoColumns = twoColumns
            }
            if let showName = quickButtons.showName {
                database.quickButtons!.showName = showName
            }
            if let enableScroll = quickButtons.enableScroll {
                database.quickButtons!.enableScroll = enableScroll
            }
            if quickButtons.disableAllButtons == true {
                for globalButton in database.globalButtons! {
                    globalButton.enabled = false
                }
            }
            for button in quickButtons.buttons ?? [] {
                for globalButton in database.globalButtons! {
                    guard button.type == globalButton.type else {
                        continue
                    }
                    if let enabled = button.enabled {
                        globalButton.enabled = enabled
                    }
                }
            }
        }
    }

    private func handleSettingsUrlsDefaultWebBrowser(settings: MoblinSettingsUrl) {
        if let webBrowser = settings.webBrowser {
            if let home = webBrowser.home {
                database.webBrowser!.home = home
            }
        }
    }

    private func handleSettingsUrlsDefault(settings: MoblinSettingsUrl) {
        handleSettingsUrlsDefaultStreams(settings: settings)
        handleSettingsUrlsDefaultQuickButtons(settings: settings)
        handleSettingsUrlsDefaultWebBrowser(settings: settings)
        store()
        makeToast(title: "URL import successful")
        updateButtonStates()
    }

    func handleSettingsUrls(urls: Set<UIOpenURLContext>) {
        for url in urls {
            guard url.url.path.isEmpty else {
                logger.warning("Custom URL path is not empty")
                continue
            }
            guard let query = url.url.query(percentEncoded: false) else {
                logger.warning("Custom URL query is missing")
                continue
            }
            let settings: MoblinSettingsUrl
            do {
                settings = try MoblinSettingsUrl.fromString(query: query)
            } catch {
                logger.error("Failed to import URL with error: \(error)")
                makeErrorToast(
                    title: String(localized: "URL import failed"),
                    subTitle: error.localizedDescription
                )
                continue
            }
            if isPresentingWizard || isPresentingSetupWizard {
                handleSettingsUrlsInWizard(settings: settings)
            } else {
                handleSettingsUrlsDefault(settings: settings)
            }
        }
    }

    private func setupPeriodicTimers() {
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true, block: { _ in
            let now = Date()
            let monotonicNow = ContinuousClock.now
            self.updateUptime(now: monotonicNow)
            self.updateRecordingLength(now: now)
            self.updateDigitalClock(now: now)
            self.updateChatSpeed()
            self.media.updateSrtSpeed()
            self.updateSpeed(now: monotonicNow)
            self.updateServersSpeed()
            if !self.database.show.audioBar {
                self.updateAudioLevel()
            }
            self.updateBondingStatistics()
            self.removeOldChatMessages(now: monotonicNow)
            self.updateLocation()
            self.updateObsSourceScreenshot()
            self.updateObsAudioVolume()
            self.updateBrowserWidgetStatus()
            self.logStatus()
            self.updateFailedVideoEffects()
        })
        Timer.scheduledTimer(withTimeInterval: 10, repeats: true, block: { _ in
            self.updateBatteryLevel()
            self.media.logStatistics()
            self.updateObsStatus()
            self.updateRemoteControlAssistantStatus()
            self.updateRemoteControlStatus()
            if self.stream.enabled {
                self.media.updateVideoStreamBitrate(bitrate: self.stream.bitrate)
            }
            self.media.logTiming()
            self.updateViewers()
            self.updateCurrentSsid()
            let (detections, filter) = self.media.getNetStream().getHistograms()
            detections.log()
            filter.log()
        })
        Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true, block: { _ in
            self.updateAdaptiveBitrate()
            if self.database.show.audioBar {
                self.updateAudioLevel()
            }
            self.updateChat()
            self.trySendNextChatPostToWatch()
            if let lastAttachCompletedTime = self.lastAttachCompletedTime,
               lastAttachCompletedTime.duration(to: .now) > .seconds(0.5)
            {
                self.updateTorch()
                self.lastAttachCompletedTime = nil
            }
        })
    }

    private func updateCurrentSsid() {
        NEHotspotNetwork.fetchCurrent(completionHandler: { network in
            self.currentWiFiSsid = network?.ssid
        })
    }

    func colorSpaceUpdated() {
        setColorSpace()
    }

    func lutEnabledUpdated() {
        if database.color!.lutEnabled && database.color!.space == .appleLog {
            media.registerEffect(lutEffect)
        } else {
            media.unregisterEffect(lutEffect)
        }
    }

    func loadLutImage(lut: SettingsColorLut) -> UIImage? {
        var image: UIImage?
        switch lut.type {
        case .bundled:
            guard let path = Bundle.main.path(forResource: "LUTs.bundle/\(lut.name).png", ofType: nil) else {
                return nil
            }
            image = UIImage(contentsOfFile: path)
        case .disk:
            if let data = try? Data(contentsOf: imageStorage.makePath(id: lut.id)) {
                image = UIImage(data: data)
            }
        }
        guard let image else {
            let message = "Failed to load LUT image \(lut.name)"
            makeErrorToast(title: message)
            logger.info(message)
            return nil
        }
        return image
    }

    func lutUpdated() {
        guard let lut = getLogLutById(id: database.color!.lut) else {
            media.unregisterEffect(lutEffect)
            return
        }
        guard let image = loadLutImage(lut: lut) else {
            return
        }
        do {
            try lutEffect.setLut(image: image)
        } catch {
            let message = "\(error)"
            makeErrorToast(title: message)
            logger.info(message)
        }
    }

    func addLut(data: Data) {
        let button = SettingsButton(name: String(localized: "My LUT"))
        button.type = .lut
        button.systemImageNameOn = "camera.filters"
        button.systemImageNameOff = "camera.filters"
        let lut = SettingsColorLut(type: .disk, name: button.name)
        lut.buttonId = button.id
        imageStorage.write(id: lut.id, data: data)
        database.color!.diskLuts!.append(lut)
        database.globalButtons!.append(button)
        store()
        updateButtonStates()
        resetSelectedScene()
    }

    func removeLut(offsets: IndexSet) {
        for offset in offsets {
            let lut = database.color!.diskLuts![offset]
            imageStorage.remove(id: lut.id)
            database.globalButtons!.removeAll(where: { $0.id == lut.buttonId })
        }
        database.color!.diskLuts!.remove(atOffsets: offsets)
        store()
        updateButtonStates()
        resetSelectedScene()
    }

    func findLutButton(lut: SettingsColorLut) -> SettingsButton? {
        return database.globalButtons!.first(where: { $0.id == lut.buttonId })
    }

    func setLutName(lut: SettingsColorLut, name: String) {
        lut.name = name
        findLutButton(lut: lut)?.name = name
        store()
    }

    private func allLuts() -> [SettingsColorLut] {
        return database.color!.bundledLuts + database.color!.diskLuts!
    }

    func getLogLutById(id: UUID) -> SettingsColorLut? {
        return allLuts().first { $0.id == id }
    }

    private func updateAdaptiveBitrate() {
        if let (lines, actions) = media.updateAdaptiveBitrate(overlay: database.debug!.srtOverlay) {
            debugLines = lines + actions
            debugLines.append("Audio/video capture delta: \(Int(1000 * media.getCaptureDelta())) ms")
            if logger.debugEnabled && isLive {
                logger.debug(lines.joined(separator: ", "))
            }
        } else if !debugLines.isEmpty {
            debugLines = []
        }
    }

    private func removeUnusedImages() {
        for id in imageStorage.ids() {
            var used = false
            for widget in database.widgets {
                if widget.type != .image {
                    continue
                }
                if widget.id == id {
                    used = true
                    break
                }
            }
            if database.color!.diskLuts!.contains(where: { lut in
                lut.id == id
            }) {
                used = true
            }
            if !used {
                logger.info("Removing unused image \(id)")
                imageStorage.remove(id: id)
            }
        }
    }

    private func updateViewers() {
        var newNumberOfViewers = 0
        var hasInfo = false
        if isTwitchViewersConfigured(), let twitchPubSub, twitchPubSub.isConnected(),
           let numberOfViewers = twitchPubSub.numberOfViewers
        {
            newNumberOfViewers += numberOfViewers
            hasInfo = true
        }
        if isKickViewersConfigured(), let numberOfViewers = kickViewers?.numberOfViewers {
            newNumberOfViewers += numberOfViewers
            hasInfo = true
        }
        var newValue: String
        if hasInfo {
            newValue = countFormatter.format(newNumberOfViewers)
        } else {
            newValue = noValue
        }
        if newValue != numberOfViewers {
            numberOfViewers = newValue
        }
    }

    private func updateAudioLevel() {
        let newAudioLevel = media.getAudioLevel()
        let newNumberOfAudioChannels = media.getNumberOfAudioChannels()
        if newNumberOfAudioChannels != numberOfAudioChannels {
            numberOfAudioChannels = newNumberOfAudioChannels
        }
        if newAudioLevel == audioLevel {
            return
        }
        if abs(audioLevel - newAudioLevel) > 5 || newAudioLevel
            .isNaN || newAudioLevel == .infinity || audioLevel.isNaN || audioLevel == .infinity
        {
            audioLevel = newAudioLevel
            sendAudioLevelToWatch()
        }
    }

    private func updateBondingStatistics() {
        if isStreamConnected() {
            if let statistics = media.srtlaConnectionStatistics() {
                bondingStatistics = statistics
                return
            }
            if let statistics = media.ristBondingStatistics() {
                bondingStatistics = statistics
                return
            }
        }
        if bondingStatistics != noValue {
            bondingStatistics = noValue
        }
    }

    func updateSrtlaPriorities() {
        media.setConnectionPriorities(connectionPriorities: stream.srt.connectionPriorities!)
    }

    func endOfChatReachedWhenPaused() {
        var numberOfPostsAppended = 0
        while numberOfPostsAppended < 5, let post = pausedChatPosts.popFirst() {
            if post.user == nil {
                if let lastPost = chatPosts.first, lastPost.user == nil {
                    continue
                }
                if pausedChatPosts.isEmpty {
                    continue
                }
            }
            chatPosts.prepend(post)
            sendChatMessageToWatch(post: post)
            numberOfChatPostsPerTick += 1
            streamTotalChatMessages += 1
            numberOfPostsAppended += 1
        }
        if numberOfPostsAppended == 0 {
            chatPaused = false
        }
    }

    func pauseChat() {
        chatPaused = true
        pausedChatPostsCount = 0
        appendChatMessage(
            user: nil,
            userColor: nil,
            segments: [],
            timestamp: "",
            timestampTime: .now,
            isAction: false,
            isAnnouncement: false,
            isFirstMessage: false,
            isSubscriber: false
        )
    }

    private func removeOldChatMessages(now: ContinuousClock.Instant) {
        if chatPaused {
            return
        }
        guard database.chat.maximumAgeEnabled! else {
            return
        }
        while let post = chatPosts.last {
            if now > post.timestampTime + .seconds(database.chat.maximumAge!) {
                chatPosts.removeLast()
            } else {
                break
            }
        }
    }

    private func updateChat() {
        if chatPaused {
            // The red line is one post.
            pausedChatPostsCount = max(pausedChatPosts.count - 1, 0)
            return
        }
        while let post = newChatPosts.popFirst() {
            if chatPosts.count > maximumNumberOfChatMessages - 1 {
                chatPosts.removeLast()
            }
            chatPosts.prepend(post)
            sendChatMessageToWatch(post: post)
            if isTextToSpeechEnabledForMessage(post: post), let user = post.user {
                let message = post.segments.filter { $0.text != nil }.map { $0.text! }.joined(separator: "")
                if !message.trimmingCharacters(in: .whitespaces).isEmpty {
                    chatTextToSpeech.say(user: user, message: message)
                }
            }
            numberOfChatPostsPerTick += 1
            streamTotalChatMessages += 1
        }
    }

    private func isTextToSpeechEnabledForMessage(post: ChatPost) -> Bool {
        guard database.chat.textToSpeechEnabled! else {
            return false
        }
        if database.chat.textToSpeechSubscribersOnly! {
            guard post.isSubscriber else {
                return false
            }
        }
        return true
    }

    private func reloadImageEffects() {
        imageEffects.removeAll()
        for scene in database.scenes {
            for widget in scene.widgets {
                guard let realWidget = findWidget(id: widget.widgetId) else {
                    continue
                }
                if realWidget.type != .image {
                    continue
                }
                guard let data = imageStorage.read(id: widget.widgetId) else {
                    continue
                }
                guard let image = UIImage(data: data) else {
                    continue
                }
                imageEffects[widget.id] = ImageEffect(
                    image: image,
                    x: widget.x,
                    y: widget.y,
                    width: widget.width,
                    height: widget.height,
                    settingName: realWidget.name
                )
            }
        }
    }

    private func handleFindFaceChanged(value: Bool) {
        DispatchQueue.main.async {
            self.findFace = value
            self.findFaceTimer?.invalidate()
            self.findFaceTimer = Timer
                .scheduledTimer(withTimeInterval: 5, repeats: false) { _ in
                    self.findFace = false
                }
        }
    }

    private func unregisterGlobalVideoEffects() {
        media.unregisterEffect(faceEffect)
        media.unregisterEffect(movieEffect)
        media.unregisterEffect(grayScaleEffect)
        media.unregisterEffect(sepiaEffect)
        media.unregisterEffect(tripleEffect)
        media.unregisterEffect(pixellateEffect)
        faceEffect = FaceEffect(fps: Float(stream.fps), onFindFaceChanged: handleFindFaceChanged(value:))
        updateFaceFilterSettings()
        movieEffect = MovieEffect()
        grayScaleEffect = GrayScaleEffect()
        sepiaEffect = SepiaEffect()
        tripleEffect = TripleEffect()
        pixellateEffect = PixellateEffect()
    }

    private func isGlobalButtonOn(type: SettingsButtonType) -> Bool {
        return database.globalButtons?.first(where: { button in
            button.type == type
        })?.isOn ?? false
    }

    private func isFaceEnabled() -> Bool {
        let settings = database.debug!.beautyFilterSettings!
        return database.debug!.beautyFilter! || settings.showBlur || settings.showMoblin || settings
            .showBeauty!
    }

    private func registerGlobalVideoEffects() -> [VideoEffect] {
        var effects: [VideoEffect] = []
        if isFaceEnabled() {
            effects.append(faceEffect)
        }
        if isGlobalButtonOn(type: .movie) {
            effects.append(movieEffect)
        }
        if isGlobalButtonOn(type: .grayScale) {
            effects.append(grayScaleEffect)
        }
        if isGlobalButtonOn(type: .sepia) {
            effects.append(sepiaEffect)
        }
        if isGlobalButtonOn(type: .triple) {
            effects.append(tripleEffect)
        }
        if isGlobalButtonOn(type: .pixellate) {
            effects.append(pixellateEffect)
        }
        return effects
    }

    func resetSelectedScene(changeScene: Bool = true) {
        if !enabledScenes.isEmpty && changeScene {
            setSceneId(id: enabledScenes[0].id)
            sceneIndex = 0
        }
        unregisterGlobalVideoEffects()
        for textEffect in textEffects.values {
            media.unregisterEffect(textEffect)
        }
        textEffects.removeAll()
        for widget in database.widgets where widget.type == .time {
            textEffects[widget.id] = TextEffect(
                format: widget.text.formatString,
                fontSize: 40,
                settingName: widget.name
            )
        }
        for browserEffect in browserEffects.values {
            media.unregisterEffect(browserEffect)
            browserEffect.stop()
        }
        browserEffects.removeAll()
        for widget in database.widgets where widget.type == .browser {
            let videoSize = media.getVideoSize()
            guard let url = URL(string: widget.browser.url) else {
                continue
            }
            browserEffects[widget.id] = BrowserEffect(
                url: url,
                widget: widget.browser,
                videoSize: videoSize,
                settingName: widget.name
            )
        }
        browsers = browserEffects.map { _, browser in
            Browser(browserEffect: browser)
        }
        drawOnStreamEffect.updateOverlay(
            videoSize: media.getVideoSize(),
            size: drawOnStreamSize,
            lines: drawOnStreamLines
        )
        for lutEffect in lutEffects.values {
            media.unregisterEffect(lutEffect)
        }
        lutEffects.removeAll()
        for lut in allLuts() {
            guard let image = loadLutImage(lut: lut) else {
                continue
            }
            let lutEffect = LutEffect()
            do {
                try lutEffect.setLut(image: image)
            } catch {
                continue
            }
            lutEffects[lut.id] = lutEffect
        }
        sceneUpdated(imageEffectChanged: true, store: false)
    }

    func store() {
        settings.store()
        sendSettingsToWatch()
    }

    func networkInterfaceNamesUpdated() {
        media.setNetworkInterfaceNames(networkInterfaceNames: database.networkInterfaceNames!)
    }

    func updateOrientationLock() {
        if stream.portrait! {
            AppDelegate.orientationLock = .portrait
            streamPreviewView.isPortrait = true
        } else {
            AppDelegate.orientationLock = .landscape
            streamPreviewView.isPortrait = false
        }
        if #available(iOS 17.0, *) {
            if stream.portrait! {
                cameraPreviewView.previewLayer.connection?.videoRotationAngle = 90
            } else {
                cameraPreviewView.previewLayer.connection?.videoRotationAngle = 0
            }
        }
    }

    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    func reloadBrowserWidgets() {
        for browser in browsers {
            browser.browserEffect.reload()
        }
    }

    func startRecording() {
        setIsRecording(value: true)
        resumeRecording()
        var subTitle: String?
        if recordingsStorage.isFull() {
            subTitle = String(localized: "Too many recordings. Deleting oldest recording.")
        }
        makeToast(title: String(localized: "Recording started"), subTitle: subTitle)
    }

    func stopRecording() {
        guard isRecording else {
            return
        }
        setIsRecording(value: false)
        makeToast(title: String(localized: "Recording stopped"))
        suspendRecording()
    }

    func resumeRecording() {
        currentRecording = recordingsStorage.createRecording(settings: stream.clone())
        let bitrate = Int(stream.recording!.videoBitrate)
        let keyFrameInterval = Int(stream.recording!.maxKeyFrameInterval)
        let audioBitrate = Int(stream.recording!.audioBitrate!)
        media.startRecording(
            url: currentRecording!.url(),
            videoCodec: stream.recording!.videoCodec,
            videoBitrate: bitrate != 0 ? bitrate : nil,
            keyFrameInterval: keyFrameInterval != 0 ? keyFrameInterval : nil,
            audioBitrate: audioBitrate != 0 ? audioBitrate : nil
        )
    }

    private func suspendRecording() {
        media.stopRecording()
        if let currentRecording {
            recordingsStorage.append(recording: currentRecording)
            recordingsStorage.store()
        }
        updateRecordingLength(now: Date())
        currentRecording = nil
    }

    func setGlobalButtonState(type: SettingsButtonType, isOn: Bool) {
        for button in database.globalButtons! where button.type == type {
            button.isOn = isOn
        }
        for pair in buttonPairs {
            if pair.first.button.type == type {
                pair.first.isOn = isOn
            }
            if let state = pair.second {
                if state.button.type == type {
                    state.isOn = isOn
                }
            }
        }
    }

    func getGlobalButton(type: SettingsButtonType) -> SettingsButton? {
        return database.globalButtons!.first(where: { $0.type == type })
    }

    private func toggleGlobalButton(type: SettingsButtonType) {
        for button in database.globalButtons! where button.type == type {
            button.isOn.toggle()
        }
        for pair in buttonPairs {
            if pair.first.button.type == type {
                pair.first.isOn.toggle()
            }
            if let state = pair.second {
                if state.button.type == type {
                    state.isOn.toggle()
                }
            }
        }
    }

    private func toggleStream() {
        if isLive {
            stopStream()
        } else {
            startStream()
        }
    }

    func setIsLive(value: Bool) {
        isLive = value
        sendIsLiveToWatch()
    }

    func setIsRecording(value: Bool) {
        isRecording = value
        setGlobalButtonState(type: .record, isOn: value)
        updateButtonStates()
        sendIsRecordingToWatch()
    }

    private func setIsMuted(value: Bool) {
        setMuteOn(value: value)
    }

    func startStream(delayed: Bool = false) {
        logger.info("stream: Start")
        guard !streaming else {
            return
        }
        if delayed && !isLive {
            return
        }
        guard stream.url != defaultStreamUrl else {
            makeErrorToast(
                title: String(
                    localized: "Please enter your stream URL in stream settings before going live."
                ),
                subTitle: String(
                    localized: "Configure it in Settings → Streams → \(stream.name) → URL."
                )
            )
            return
        }
        setIsLive(value: true)
        streaming = true
        streamTotalBytes = 0
        streamTotalChatMessages = 0
        updateScreenAutoOff()
        startNetStream()
        if stream.recording!.autoStartRecording! {
            startRecording()
        }
        streamingHistoryStream = StreamingHistoryStream(settings: stream.clone())
        streamingHistoryStream!.updateHighestThermalState(thermalState: ThermalState(from: thermalState))
        streamingHistoryStream!.updateLowestBatteryLevel(level: batteryLevel)
    }

    func stopStream() {
        setIsLive(value: false)
        updateScreenAutoOff()
        realtimeIrl?.stop()
        if !streaming {
            return
        }
        logger.info("stream: Stop")
        streamTotalBytes += UInt64(media.streamTotal())
        streaming = false
        if stream.recording!.autoStopRecording! {
            stopRecording()
        }
        stopNetStream()
        streamState = .disconnected
        if let streamingHistoryStream {
            streamingHistoryStream.stopTime = Date()
            streamingHistoryStream.totalBytes = streamTotalBytes
            streamingHistoryStream.numberOfChatMessages = streamTotalChatMessages
            streamingHistory.append(stream: streamingHistoryStream)
            streamingHistory.store()
        }
    }

    func updateScreenAutoOff() {
        UIApplication.shared.isIdleTimerDisabled = (showingRemoteControl || isLive)
    }

    private func startNetStream(reconnect _: Bool = false) {
        streamState = .connecting
        latestLowBitrateTime = .now
        switch stream.getProtocol() {
        case .rtmp:
            media.rtmpStartStream(url: stream.url,
                                  targetBitrate: stream.bitrate,
                                  adaptiveBitrate: stream.rtmp!.adaptiveBitrateEnabled)
            updateAdaptiveBitrateRtmpIfEnabled()
        case .srt:
            payloadSize = stream.srt.mpegtsPacketsPerPacket * MpegTsPacket.size
            media.srtStartStream(
                isSrtla: stream.isSrtla(),
                url: stream.url,
                reconnectTime: 5,
                targetBitrate: stream.bitrate,
                adaptiveBitrate: stream.srt.adaptiveBitrateEnabled!,
                latency: stream.srt.latency,
                overheadBandwidth: database.debug!.srtOverheadBandwidth!,
                maximumBandwidthFollowInput: database.debug!.maximumBandwidthFollowInput!,
                mpegtsPacketsPerPacket: stream.srt.mpegtsPacketsPerPacket,
                networkInterfaceNames: database.networkInterfaceNames!,
                connectionPriorities: stream.srt.connectionPriorities!
            )
            updateAdaptiveBitrateSrtIfEnabled(stream: stream)
        case .irltk:
            payloadSize = stream.srt.mpegtsPacketsPerPacket * MpegTsPacket.size
            media.irlToolkitStartStream(
                url: stream.url,
                reconnectTime: 5,
                targetBitrate: stream.bitrate,
                adaptiveBitrate: stream.srt.adaptiveBitrateEnabled!,
                latency: stream.srt.latency,
                overheadBandwidth: database.debug!.srtOverheadBandwidth!,
                maximumBandwidthFollowInput: database.debug!.maximumBandwidthFollowInput!,
                mpegtsPacketsPerPacket: stream.srt.mpegtsPacketsPerPacket,
                networkInterfaceNames: database.networkInterfaceNames!,
                connectionPriorities: stream.srt.connectionPriorities!
            )
            updateAdaptiveBitrateSrtIfEnabled(stream: stream)
        case .rist:
            media.ristStartStream(url: stream.url,
                                  bonding: stream.rist!.bonding,
                                  targetBitrate: stream.bitrate,
                                  adaptiveBitrate: stream.rist!.adaptiveBitrateEnabled)
            updateAdaptiveBitrateRistIfEnabled()
        }
        updateSpeed(now: .now)
    }

    private func stopNetStream(reconnect: Bool = false) {
        reconnectTimer?.invalidate()
        media.rtmpStopStream()
        media.srtStopStream()
        media.ristStopStream()
        media.irlToolkitStopStream()
        streamStartTime = nil
        updateUptime(now: .now)
        updateSpeed(now: .now)
        updateAudioLevel()
        bondingStatistics = noValue
        if !reconnect {
            makeStreamEndedToast()
        }
    }

    func setCurrentStream(stream: SettingsStream) {
        stream.enabled = true
        for ostream in database.streams where ostream.id != stream.id {
            ostream.enabled = false
        }
        currentStreamId = stream.id
        updateOrientationLock()
    }

    func setCurrentStream(streamId: UUID) -> Bool {
        guard let stream = findStream(id: streamId) else {
            return false
        }
        setCurrentStream(stream: stream)
        return true
    }

    private func findStream(id: UUID) -> SettingsStream? {
        return database.streams.first { stream in
            stream.id == id
        }
    }

    func reloadStream() {
        cameraPosition = nil
        stopRecording()
        stopStream()
        setNetStream()
        setStreamResolution()
        setStreamFPS()
        setColorSpace()
        setStreamCodec()
        setStreamKeyFrameInterval()
        setStreamBitrate(stream: stream)
        setAudioStreamBitrate(stream: stream)
        setAudioStreamFormat(format: .aac)
        setAudioChannelsMap(channelsMap: [
            0: database.audio!.audioOutputToInputChannelsMap!.channel1,
            1: database.audio!.audioOutputToInputChannelsMap!.channel2,
        ])
        reloadConnections()
        resetChat()
        reloadLocation()
        reloadRtmpStreams()
    }

    func reloadChats() {
        reloadTwitchChat()
        reloadKickPusher()
        reloadYouTubeLiveChat()
        reloadAfreecaTvChat()
        reloadOpenStreamingPlatformChat()
    }

    private func reloadConnections() {
        reloadChats()
        reloadTwitchPubSub()
        reloadObsWebSocket()
        reloadRemoteControlStreamer()
        reloadRemoteControlAssistant()
        reloadKickViewers()
    }

    func storeAndReloadStreamIfEnabled(stream: SettingsStream) {
        store()
        if stream.enabled {
            reloadStream()
            sceneUpdated()
        }
    }

    private func setNetStream() {
        media.setNetStream(proto: stream.getProtocol())
        updateTorch()
        updateMute()
        streamPreviewView.attachStream(media.getNetStream())
        setLowFpsImage()
    }

    private func showPreset(preset: SettingsZoomPreset) -> Bool {
        let x = preset.x!
        return x >= cameraZoomXMinimum && x <= cameraZoomXMaximum
    }

    func backZoomPresets() -> [SettingsZoomPreset] {
        return database.zoom.back.filter { showPreset(preset: $0) }
    }

    func frontZoomPresets() -> [SettingsZoomPreset] {
        return database.zoom.front.filter { showPreset(preset: $0) }
    }

    private func getPreset(preset: AVCaptureSession.Preset) -> AVCaptureSession.Preset {
        return preset
    }

    private func setStreamResolution() {
        switch stream.resolution {
        case .r3840x2160:
            media.setVideoSessionPreset(preset: getPreset(preset: .hd4K3840x2160))
            media.setVideoSize(width: 3840, height: 2160)
        case .r1920x1080:
            media.setVideoSessionPreset(preset: getPreset(preset: .hd1920x1080))
            media.setVideoSize(width: 1920, height: 1080)
        case .r1280x720:
            media.setVideoSessionPreset(preset: getPreset(preset: .hd1280x720))
            media.setVideoSize(width: 1280, height: 720)
        case .r854x480:
            media.setVideoSessionPreset(preset: getPreset(preset: .hd1280x720))
            media.setVideoSize(width: 854, height: 480)
        case .r640x360:
            media.setVideoSessionPreset(preset: getPreset(preset: .hd1280x720))
            media.setVideoSize(width: 640, height: 360)
        case .r426x240:
            media.setVideoSessionPreset(preset: getPreset(preset: .hd1280x720))
            media.setVideoSize(width: 426, height: 240)
        }
    }

    func setStreamFPS() {
        media.setStreamFPS(fps: stream.fps)
    }

    func setColorSpace() {
        var colorSpace: AVCaptureColorSpace
        switch database.color!.space {
        case .srgb:
            colorSpace = .sRGB
        case .p3D65:
            colorSpace = .P3_D65
        case .appleLog:
            if #available(iOS 17.0, *) {
                colorSpace = .appleLog
            } else {
                colorSpace = .sRGB
            }
        }
        media.setColorSpace(colorSpace: colorSpace, onComplete: {
            DispatchQueue.main.async {
                if let x = self.setCameraZoomX(x: self.zoomX) {
                    self.setZoomX(x: x)
                }
                self.lutEnabledUpdated()
            }
        })
    }

    func setStreamBitrate(stream: SettingsStream) {
        media.setVideoStreamBitrate(bitrate: stream.bitrate)
    }

    private func getBitratePresetByBitrate(bitrate: UInt32) -> SettingsBitratePreset? {
        return database.bitratePresets.first(where: { preset in
            preset.bitrate == bitrate
        })
    }

    func setBitrate(bitrate: UInt32) {
        stream.bitrate = bitrate
        guard let preset = getBitratePresetByBitrate(bitrate: bitrate) else {
            return
        }
        remoteControlStreamer?.stateChanged(state: RemoteControlState(bitrate: preset.id))
    }

    func setAudioStreamBitrate(stream: SettingsStream) {
        media.setAudioStreamBitrate(bitrate: stream.audioBitrate!)
    }

    func setAudioStreamFormat(format: AudioCodecOutputSettings.Format) {
        media.setAudioStreamFormat(format: format)
    }

    func setAudioChannelsMap(channelsMap: [Int: Int]) {
        media.setAudioChannelsMap(channelsMap: channelsMap)
    }

    private func setStreamCodec() {
        switch stream.codec {
        case .h264avc:
            media.setVideoProfile(profile: kVTProfileLevel_H264_Main_AutoLevel)
        case .h265hevc:
            media.setVideoProfile(profile: kVTProfileLevel_HEVC_Main_AutoLevel)
        }
        media.setAllowFrameReordering(value: stream.bFrames!)
    }

    private func setStreamKeyFrameInterval() {
        media.setStreamKeyFrameInterval(seconds: stream.maxKeyFrameInterval!)
    }

    func isStreamConfigured() -> Bool {
        return stream != fallbackStream
    }

    func isChatConfigured() -> Bool {
        return isTwitchChatConfigured() || isKickPusherConfigured() ||
            isYouTubeLiveChatConfigured() || isAfreecaTvChatConfigured() ||
            isOpenStreamingPlatformChatConfigured()
    }

    func isViewersConfigured() -> Bool {
        return isTwitchViewersConfigured() || isKickViewersConfigured()
    }

    func isTwitchViewersConfigured() -> Bool {
        return stream.twitchEnabled! && stream.twitchChannelId != ""
    }

    func isTwitchChatConfigured() -> Bool {
        return database.chat.enabled! && stream.twitchEnabled! && stream.twitchChannelName != ""
    }

    func isTwitchChatConnected() -> Bool {
        return twitchChat?.isConnected() ?? false
    }

    func hasTwitchChatEmotes() -> Bool {
        return twitchChat?.hasEmotes() ?? false
    }

    func isTwitchPubSubConnected() -> Bool {
        return twitchPubSub?.isConnected() ?? false
    }

    func isKickPusherConfigured() -> Bool {
        return database.chat.enabled! && stream
            .kickEnabled! && (stream.kickChatroomId != "" || stream.kickChannelName != "")
    }

    func isKickPusherConnected() -> Bool {
        return kickPusher?.isConnected() ?? false
    }

    func hasKickPusherEmotes() -> Bool {
        return kickPusher?.hasEmotes() ?? false
    }

    func isKickViewersConfigured() -> Bool {
        return stream.kickEnabled! && stream.kickChannelName != ""
    }

    func isYouTubeLiveChatConfigured() -> Bool {
        return database.chat.enabled! && stream.youTubeEnabled! && stream.youTubeVideoId! != ""
    }

    func isYouTubeLiveChatConnected() -> Bool {
        return youTubeLiveChat?.isConnected() ?? false
    }

    func hasYouTubeLiveChatEmotes() -> Bool {
        return youTubeLiveChat?.hasEmotes() ?? false
    }

    func isAfreecaTvChatConfigured() -> Bool {
        return database.chat.enabled! && stream.afreecaTvEnabled! && stream
            .afreecaTvChannelName! != "" && stream
            .afreecaTvStreamId! != ""
    }

    func isAfreecaTvChatConnected() -> Bool {
        return afreecaTvChat?.isConnected() ?? false
    }

    func hasAfreecaTvChatEmotes() -> Bool {
        return afreecaTvChat?.hasEmotes() ?? false
    }

    func isOpenStreamingPlatformChatConfigured() -> Bool {
        return database.chat.enabled! && stream.openStreamingPlatformEnabled! && stream
            .openStreamingPlatformUrl! != "" && stream
            .openStreamingPlatformChannelId! != ""
    }

    func isOpenStreamingPlatformChatConnected() -> Bool {
        return openStreamingPlatformChat?.isConnected() ?? false
    }

    func hasOpenStreamingPlatformChatEmotes() -> Bool {
        return openStreamingPlatformChat?.hasEmotes() ?? false
    }

    func isChatConnected() -> Bool {
        if isTwitchChatConfigured() && !isTwitchChatConnected() {
            return false
        }
        if isKickPusherConfigured() && !isKickPusherConnected() {
            return false
        }
        if isYouTubeLiveChatConfigured() && !isYouTubeLiveChatConnected() {
            return false
        }
        if isAfreecaTvChatConfigured() && !isAfreecaTvChatConnected() {
            return false
        }
        if isOpenStreamingPlatformChatConfigured() && !isOpenStreamingPlatformChatConnected() {
            return false
        }
        return true
    }

    func hasChatEmotes() -> Bool {
        return hasTwitchChatEmotes() || hasKickPusherEmotes() ||
            hasYouTubeLiveChatEmotes() || hasAfreecaTvChatEmotes() || hasOpenStreamingPlatformChatEmotes()
    }

    func isStreamConnected() -> Bool {
        return streamState == .connected
    }

    func isStreaming() -> Bool {
        return streaming
    }

    private func resetChat() {
        chatPostsRate = "0.0/min"
        chatPostsTotal = 0
        chatSpeedTicks = 0
        chatPosts = []
        pausedChatPosts = []
        newChatPosts = []
        numberOfChatPostsPerTick = 0
        chatPostsRatePerSecond = 0
        chatPostsRatePerMinute = 0
        numberOfChatPostsPerMinute = 0
        chatTextToSpeech.reset(running: true)
    }

    private func reloadTwitchChat() {
        twitchChat.stop()
        if isTwitchChatConfigured() {
            twitchChat.start(
                channelName: stream.twitchChannelName,
                channelId: stream.twitchChannelId,
                settings: stream.chat!
            )
        }
    }

    private func reloadTwitchPubSub() {
        twitchPubSub?.stop()
        if isTwitchViewersConfigured() {
            twitchPubSub = TwitchPubSub(channelId: stream.twitchChannelId)
            twitchPubSub!.start()
        }
    }

    private func reloadKickViewers() {
        kickViewers?.stop()
        if isKickViewersConfigured() {
            kickViewers = KickViewers()
            kickViewers!.start(channelName: stream.kickChannelName!)
        }
    }

    private func reloadKickPusher() {
        kickPusher?.stop()
        kickPusher = nil
        if isKickPusherConfigured() {
            kickPusher = KickPusher(model: self,
                                    channelId: stream.kickChatroomId,
                                    channelName: stream.kickChannelName!,
                                    settings: stream.chat!)
            kickPusher!.start()
        }
    }

    private func reloadYouTubeLiveChat() {
        youTubeLiveChat?.stop()
        youTubeLiveChat = nil
        if isYouTubeLiveChatConfigured() {
            youTubeLiveChat = YouTubeLiveChat(
                model: self,
                videoId: stream.youTubeVideoId!,
                settings: stream.chat!
            )
            youTubeLiveChat!.start()
        }
    }

    private func reloadAfreecaTvChat() {
        afreecaTvChat?.stop()
        afreecaTvChat = nil
        if isAfreecaTvChatConfigured() {
            afreecaTvChat = AfreecaTvChat(
                model: self,
                channelName: stream.afreecaTvChannelName!,
                streamId: stream.afreecaTvStreamId!
            )
            afreecaTvChat!.start()
        }
    }

    private func reloadOpenStreamingPlatformChat() {
        openStreamingPlatformChat?.stop()
        openStreamingPlatformChat = nil
        if isOpenStreamingPlatformChatConfigured() {
            openStreamingPlatformChat = OpenStreamingPlatformChat(
                model: self,
                url: stream.openStreamingPlatformUrl!,
                channelId: stream.openStreamingPlatformChannelId!
            )
            openStreamingPlatformChat!.start()
        }
    }

    private func reloadObsWebSocket() {
        obsWebSocket?.stop()
        obsWebSocket?.onSceneChanged = nil
        obsWebSocket?.onStreamStatusChanged = nil
        obsWebSocket?.onRecordStatusChanged = nil
        obsWebSocket?.onAudioVolume = nil
        obsWebSocket = nil
        guard isObsRemoteControlConfigured() else {
            return
        }
        guard let url = URL(string: stream.obsWebSocketUrl!) else {
            return
        }
        obsWebSocket = ObsWebSocket(
            url: url,
            password: stream.obsWebSocketPassword!,
            onConnected: {
                self.updateObsStatus()
            }
        )
        obsWebSocket!.onSceneChanged = handleObsSceneChanged
        obsWebSocket!.onStreamStatusChanged = handleObsStreamStatusChanged
        obsWebSocket!.onRecordStatusChanged = handleObsRecordStatusChanged
        obsWebSocket!.onAudioVolume = handleAudioVolume
        obsWebSocket!.start()
    }

    func twitchEnabledUpdated() {
        reloadTwitchPubSub()
        reloadTwitchChat()
        resetChat()
    }

    func twitchChannelNameUpdated() {
        reloadTwitchChat()
        resetChat()
    }

    func twitchChannelIdUpdated() {
        reloadTwitchPubSub()
        reloadTwitchChat()
        resetChat()
    }

    func kickEnabledUpdated() {
        reloadKickPusher()
        resetChat()
    }

    func kickChannelNameUpdated() {
        reloadKickPusher()
        reloadKickViewers()
        resetChat()
    }

    func youTubeEnabledUpdated() {
        reloadYouTubeLiveChat()
        resetChat()
    }

    func youTubeVideoIdUpdated() {
        reloadYouTubeLiveChat()
        resetChat()
    }

    func afreecaTvEnabledUpdated() {
        reloadAfreecaTvChat()
        resetChat()
    }

    func afreecaTvChannelNameUpdated() {
        reloadAfreecaTvChat()
        resetChat()
    }

    func afreecaTvStreamIdUpdated() {
        reloadAfreecaTvChat()
        resetChat()
    }

    func openStreamingPlatformEnabledUpdated() {
        reloadOpenStreamingPlatformChat()
        resetChat()
    }

    func openStreamingPlatformUrlUpdated() {
        reloadOpenStreamingPlatformChat()
        resetChat()
    }

    func openStreamingPlatformRoomUpdated() {
        reloadOpenStreamingPlatformChat()
        resetChat()
    }

    func obsWebSocketEnabledUpdated() {
        reloadObsWebSocket()
    }

    func obsWebSocketUrlUpdated() {
        reloadObsWebSocket()
    }

    func obsWebSocketPasswordUpdated() {
        reloadObsWebSocket()
    }

    func bttvEmotesEnabledUpdated() {
        reloadChats()
    }

    func ffzEmotesEnabledUpdated() {
        reloadChats()
    }

    func seventvEmotesEnabledUpdated() {
        reloadChats()
    }

    func obsStartStream() {
        obsWebSocket?.startStream(onSuccess: {}, onError: { message in
            DispatchQueue.main.async {
                self.makeErrorToast(title: String(localized: "Failed to start OBS stream"),
                                    subTitle: message)
            }
        })
    }

    func obsStopStream() {
        obsWebSocket?.stopStream(onSuccess: {}, onError: { message in
            DispatchQueue.main.async {
                self.makeErrorToast(title: String(localized: "Failed to stop OBS stream"),
                                    subTitle: message)
            }
        })
    }

    func obsStartRecording() {
        obsWebSocket?.startRecord(onSuccess: {}, onError: { message in
            DispatchQueue.main.async {
                self.makeErrorToast(title: String(localized: "Failed to start OBS recording"),
                                    subTitle: message)
            }
        })
    }

    func obsStopRecording() {
        obsWebSocket?.stopRecord(onSuccess: {}, onError: { message in
            DispatchQueue.main.async {
                self.makeErrorToast(title: String(localized: "Failed to stop OBS recording"),
                                    subTitle: message)
            }
        })
    }

    func obsFixStream() {
        obsFixOngoing = true
        obsWebSocket?.setInputSettings(inputName: stream.obsSourceName!,
                                       onSuccess: {
                                           self.obsFixOngoing = false
                                       }, onError: { message in
                                           self.obsFixOngoing = false
                                           DispatchQueue.main.async {
                                               self.makeErrorToast(
                                                   title: String(localized: "Failed to fix OBS input"),
                                                   subTitle: message
                                               )
                                           }
                                       })
    }

    func startObsAudioVolume() {
        obsAudioVolumeLatest = noValue
        obsWebSocket?.startAudioVolume()
    }

    func stopObsAudioVolume() {
        obsWebSocket?.stopAudioVolume()
    }

    private func updateObsAudioVolume() {
        if obsAudioVolumeLatest != obsAudioVolume {
            obsAudioVolume = obsAudioVolumeLatest
        }
    }

    func updateBrowserWidgetStatus() {
        browserWidgetsStatusChanged = false
        var messages: [String] = []
        for browser in browsers {
            let progress = browser.browserEffect.progress
            if browser.browserEffect.isLoaded {
                messages.append("\(browser.browserEffect.host): \(progress)%")
                if progress != 100 || browser.browserEffect.startLoadingTime + .seconds(5) > .now {
                    browserWidgetsStatusChanged = true
                }
            }
        }
        var message: String
        if messages.isEmpty {
            message = noValue
        } else {
            message = messages.joined(separator: ", ")
        }
        if browserWidgetsStatus != message {
            browserWidgetsStatus = message
        }
    }

    private func logStatus() {
        if logger.debugEnabled && isLive {
            logger.debug("Status: Bitrate: \(speedAndTotal), Uptime: \(uptime)")
        }
    }

    private func updateFailedVideoEffects() {
        let newFailedVideoEffect = media.getFailedVideoEffect()
        if newFailedVideoEffect != failedVideoEffect {
            if let newFailedVideoEffect {
                makeErrorToast(title: "Failed to render \(newFailedVideoEffect)")
            }
            failedVideoEffect = newFailedVideoEffect
        }
    }

    func setLowFpsImage() {
        media.setLowFpsImage(enabled: isWatchReachable() || isRemoteControlStreamerConnected())
    }

    func toggleLocalOverlays() {
        showLocalOverlays.toggle()
    }

    func toggleBrowser() {
        showBrowser.toggle()
    }

    func startObsSourceScreenshot() {
        obsScreenshot = nil
        obsSourceFetchScreenshot = true
        obsSourceScreenshotIsFetching = false
    }

    func stopObsSourceScreenshot() {
        obsSourceFetchScreenshot = false
    }

    private func updateObsSourceScreenshot() {
        guard obsSourceFetchScreenshot else {
            return
        }
        guard !obsSourceScreenshotIsFetching else {
            return
        }
        guard !obsCurrentScenePicker.isEmpty else {
            return
        }
        obsWebSocket?.getSourceScreenshot(name: obsCurrentScenePicker, onSuccess: { data in
            let screenshot = UIImage(data: data)?.cgImage
            DispatchQueue.main.async {
                self.obsScreenshot = screenshot
                self.obsSourceScreenshotIsFetching = false
            }
        }, onError: { message in
            logger.debug("Failed to update screenshot with error \(message)")
            DispatchQueue.main.async {
                self.obsScreenshot = nil
                self.obsSourceScreenshotIsFetching = false
            }
        })
    }

    func setObsAudioDelay(offset: Int) {
        guard !stream.obsSourceName!.isEmpty else {
            return
        }
        obsWebSocket?.setInputAudioSyncOffset(name: stream.obsSourceName!, offsetInMs: offset, onSuccess: {
            DispatchQueue.main.async {
                self.updateObsAudioDelay()
            }
        }, onError: { _ in
        })
    }

    func updateObsAudioDelay() {
        guard !stream.obsSourceName!.isEmpty else {
            return
        }
        obsWebSocket?.getInputAudioSyncOffset(name: stream.obsSourceName!, onSuccess: { offset in
            DispatchQueue.main.async {
                self.obsAudioDelay = offset
            }
        }, onError: { _ in
        })
    }

    private func handleObsSceneChanged(name: String) {
        DispatchQueue.main.async {
            self.obsCurrentScene = name
        }
    }

    private func handleObsStreamStatusChanged(active: Bool, state: ObsOutputState? = nil) {
        DispatchQueue.main.async {
            self.obsStreaming = active
            if let state {
                self.obsStreamingState = state
            } else if active {
                self.obsStreamingState = .started
            } else {
                self.obsStreamingState = .stopped
            }
        }
    }

    private func handleObsRecordStatusChanged(active: Bool, state: ObsOutputState? = nil) {
        DispatchQueue.main.async {
            self.obsRecording = active
            if let state {
                self.obsRecordingState = state
            } else if active {
                self.obsRecordingState = .started
            } else {
                self.obsRecordingState = .stopped
            }
        }
    }

    private func handleAudioVolume(volumes: [ObsAudioInputVolume]) {
        DispatchQueue.main.async {
            guard let volume = volumes.first(where: { volume in
                volume.name == self.stream.obsSourceName!
            }) else {
                self
                    .obsAudioVolumeLatest =
                    String(localized: "Source \(self.stream.obsSourceName!) not found")
                return
            }
            var values: [String] = []
            for volume in volume.volumes {
                if volume.isInfinite {
                    values.append(String(localized: "Muted"))
                } else {
                    values.append(String(localized: "\(formatOneDecimal(value: volume)) dB"))
                }
            }
            self.obsAudioVolumeLatest = values.joined(separator: ", ")
        }
    }

    private func appendChatPost(post: ChatPost) {
        appendChatMessage(user: post.user,
                          userColor: post.userColor,
                          segments: post.segments,
                          timestamp: post.timestamp,
                          timestampTime: post.timestampTime,
                          isAction: post.isAction,
                          isAnnouncement: post.isAnnouncement,
                          isFirstMessage: post.isFirstMessage,
                          isSubscriber: post.isSubscriber)
    }

    func appendChatMessage(
        user: String?,
        userColor: String?,
        segments: [ChatPostSegment],
        timestamp: String,
        timestampTime: ContinuousClock.Instant,
        isAction: Bool,
        isAnnouncement: Bool,
        isFirstMessage: Bool,
        isSubscriber: Bool
    ) {
        if database.chat.usernamesToIgnore!.contains(where: { user == $0.value }) {
            return
        }
        let post = ChatPost(
            id: chatPostId,
            user: user,
            userColor: userColor,
            segments: segments,
            timestamp: timestamp,
            timestampTime: timestampTime,
            isAction: isAction,
            isAnnouncement: isAnnouncement,
            isFirstMessage: isFirstMessage,
            isSubscriber: isSubscriber
        )
        chatPostId += 1
        if chatPaused {
            if pausedChatPosts.count < 2 * maximumNumberOfChatMessages {
                pausedChatPosts.append(post)
            }
        } else {
            newChatPosts.append(post)
        }
    }

    func reloadChatMessages() {
        let posts = chatPosts
        chatPosts = []
        for post in posts {
            appendChatPost(post: post)
        }
    }

    func toggleBlackScreen() {
        blackScreen.toggle()
    }

    func toggleInteractiveChat() {
        interactiveChat.toggle()
    }

    func findWidget(id: UUID) -> SettingsWidget? {
        for widget in database.widgets where widget.id == id {
            return widget
        }
        return nil
    }

    func findEnabledScene(id: UUID) -> SettingsScene? {
        for scene in enabledScenes where id == scene.id {
            return scene
        }
        return nil
    }

    func getSceneName(id: UUID) -> String {
        return database.scenes.first { scene in
            scene.id == id
        }?.name ?? "Unknown"
    }

    private func sceneUpdatedOff() {
        unregisterGlobalVideoEffects()
        for imageEffect in imageEffects.values {
            media.unregisterEffect(imageEffect)
        }
        for textEffect in textEffects.values {
            media.unregisterEffect(textEffect)
        }
        for browserEffect in browserEffects.values {
            media.unregisterEffect(browserEffect)
            browserEffect.stop()
        }
        media.unregisterEffect(drawOnStreamEffect)
        media.unregisterEffect(lutEffect)
        for lutEffect in lutEffects.values {
            media.unregisterEffect(lutEffect)
        }
    }

    private func attachSingleLayout(scene: SettingsScene) {
        isFrontCameraSelected = false
        switch scene.cameraPosition! {
        case .back:
            attachCamera(position: .back)
        case .front:
            attachCamera(position: .front)
            isFrontCameraSelected = true
        case .rtmp:
            attachRtmpCamera(cameraId: scene.rtmpCameraId!)
        case .srtla:
            attachRtmpCamera(cameraId: scene.srtlaCameraId!)
        case .external:
            attachExternalCamera(cameraId: scene.externalCameraId!)
        }
    }

    func listCameraPositions() -> [(String, String)] {
        return backCameras.map {
            ($0.id, "Back \($0.name)")
        } + frontCameras.map {
            ($0.id, "Front \($0.name)")
        } + externalCameras.map {
            ($0.id, $0.name)
        } + rtmpCameras().map {
            ($0, $0)
        } + srtlaCameras().map {
            ($0, $0)
        }
    }

    func isBackCamera(cameraId: String) -> Bool {
        return backCameras.contains(where: { $0.id == cameraId })
    }

    func isFrontCamera(cameraId: String) -> Bool {
        return frontCameras.contains(where: { $0.id == cameraId })
    }

    func getCameraPositionId(scene: SettingsScene?) -> String {
        guard let scene else {
            return ""
        }
        switch scene.cameraPosition! {
        case .rtmp:
            if let stream = getRtmpStream(id: scene.rtmpCameraId!) {
                return stream.camera()
            } else {
                return ""
            }
        case .srtla:
            if let stream = getSrtlaStream(id: scene.srtlaCameraId!) {
                return stream.camera()
            } else {
                return ""
            }
        case .external:
            if !scene.externalCameraId!.isEmpty {
                return scene.externalCameraId!
            } else {
                return ""
            }
        case .back:
            if !scene.backCameraId!.isEmpty {
                return scene.backCameraId!
            } else {
                return ""
            }
        case .front:
            if !scene.frontCameraId!.isEmpty {
                return scene.frontCameraId!
            } else {
                return ""
            }
        }
    }

    func getCameraPositionName(scene: SettingsScene?) -> String {
        guard let scene else {
            return "Unknown"
        }
        switch scene.cameraPosition! {
        case .rtmp:
            if let stream = getRtmpStream(id: scene.rtmpCameraId!) {
                return stream.camera()
            } else {
                return "Unknown"
            }
        case .srtla:
            if let stream = getSrtlaStream(id: scene.srtlaCameraId!) {
                return stream.camera()
            } else {
                return "Unknown"
            }
        case .external:
            if !scene.externalCameraName!.isEmpty {
                return scene.externalCameraName!
            } else {
                return "Unknown"
            }
        case .back:
            if let camera = backCameras.first(where: { $0.id == scene.backCameraId! }) {
                return "Back \(camera.name)"
            } else {
                return "Unknown"
            }
        case .front:
            if let camera = frontCameras.first(where: { $0.id == scene.frontCameraId! }) {
                return "Front \(camera.name)"
            } else {
                return "Unknown"
            }
        }
    }

    func getExternalCameraName(cameraId: String) -> String {
        if let camera = externalCameras.first(where: { camera in
            camera.id == cameraId
        }) {
            return camera.name
        } else {
            return "Unknown"
        }
    }

    private func rtmpCameras() -> [String] {
        return database.rtmpServer!.streams.map { stream in
            stream.camera()
        }
    }

    func getRtmpStream(id: UUID) -> SettingsRtmpServerStream? {
        return database.rtmpServer!.streams.first { stream in
            stream.id == id
        }
    }

    func getRtmpStream(camera: String) -> SettingsRtmpServerStream? {
        return database.rtmpServer!.streams.first { stream in
            camera == stream.camera()
        }
    }

    func getRtmpStream(streamKey: String) -> SettingsRtmpServerStream? {
        return database.rtmpServer!.streams.first { stream in
            stream.streamKey == streamKey
        }
    }

    func stopAllRtmpStreams() {
        for stream in database.rtmpServer!.streams {
            media.removeRtmpCamera(cameraId: stream.id)
            media.removeRtmpAudio(cameraId: stream.id)
        }
    }

    func isRtmpStreamConnected(streamKey: String) -> Bool {
        return rtmpServer?.isStreamConnected(streamKey: streamKey) ?? false
    }

    private func findSceneWidget(scene: SettingsScene, widgetId: UUID) -> SettingsSceneWidget? {
        return scene.widgets.first(where: { $0.widgetId == widgetId })
    }

    private func sceneUpdatedOn(scene: SettingsScene) {
        var effects: [VideoEffect] = []
        if database.color!.lutEnabled && database.color!.space == .appleLog {
            effects.append(lutEffect)
        }
        for lut in allLuts() {
            guard let button = findLutButton(lut: lut), button.enabled!, button.isOn else {
                continue
            }
            guard let lutEffect = lutEffects[lut.id] else {
                continue
            }
            effects.append(lutEffect)
        }
        effects += registerGlobalVideoEffects()
        var usedBrowserEffects: [BrowserEffect] = []
        for sceneWidget in scene.widgets.filter({ $0.enabled }) {
            guard let widget = findWidget(id: sceneWidget.widgetId) else {
                continue
            }
            switch widget.type {
            case .image:
                if let imageEffect = imageEffects[sceneWidget.id] {
                    effects.append(imageEffect)
                }
            case .time:
                if let textEffect = textEffects[widget.id] {
                    textEffect.x = sceneWidget.x
                    textEffect.y = sceneWidget.y
                    effects.append(textEffect)
                }
            case .videoEffect:
                break
            case .browser:
                if let browserEffect = browserEffects[widget.id],
                   !usedBrowserEffects.contains(browserEffect)
                {
                    browserEffect.setSceneWidget(
                        sceneWidget: sceneWidget,
                        crops: findWidgetCrops(scene: scene, sourceWidgetId: widget.id)
                    )
                    if !browserEffect.audioOnly {
                        effects.append(browserEffect)
                    }
                    usedBrowserEffects.append(browserEffect)
                }
            case .crop:
                if let browserEffect = browserEffects[widget.crop!.sourceWidgetId],
                   !usedBrowserEffects.contains(browserEffect)
                {
                    browserEffect.setSceneWidget(
                        sceneWidget: findSceneWidget(scene: scene, widgetId: widget.crop!.sourceWidgetId),
                        crops: findWidgetCrops(scene: scene, sourceWidgetId: widget.crop!.sourceWidgetId)
                    )
                    if !browserEffect.audioOnly {
                        effects.append(browserEffect)
                    }
                    usedBrowserEffects.append(browserEffect)
                }
            }
        }
        if !drawOnStreamLines.isEmpty {
            effects.append(drawOnStreamEffect)
        }
        media.setPendingAfterAttachEffects(effects: effects)
        for browserEffect in browserEffects.values where !usedBrowserEffects.contains(browserEffect) {
            browserEffect.setSceneWidget(sceneWidget: nil, crops: [])
        }
        attachSingleLayout(scene: scene)
    }

    private func findWidgetCrops(scene: SettingsScene, sourceWidgetId: UUID) -> [WidgetCrop] {
        var crops: [WidgetCrop] = []
        for sceneWidget in scene.widgets.filter({ $0.enabled }) {
            guard let widget = findWidget(id: sceneWidget.widgetId) else {
                logger.error("Widget not found")
                continue
            }
            guard widget.type == .crop else {
                continue
            }
            let crop = widget.crop!
            guard crop.sourceWidgetId == sourceWidgetId else {
                continue
            }
            crops.append(WidgetCrop(position: .init(x: sceneWidget.x, y: sceneWidget.y),
                                    crop: .init(
                                        x: crop.x,
                                        y: crop.y,
                                        width: crop.width,
                                        height: crop.height
                                    )))
        }
        return crops
    }

    func setSceneId(id: UUID) {
        selectedSceneId = id
        remoteControlStreamer?.stateChanged(state: RemoteControlState(scene: id))
    }

    private func selectScene(id: UUID) {
        if let index = enabledScenes.firstIndex(where: { scene in
            scene.id == id
        }) {
            sceneIndex = index
            setSceneId(id: id)
        }
    }

    func sceneUpdated(imageEffectChanged: Bool = false, store: Bool = true) {
        if store {
            self.store()
        }
        if imageEffectChanged {
            reloadImageEffects()
        }
        guard let scene = findEnabledScene(id: selectedSceneId) else {
            sceneUpdatedOff()
            return
        }
        sceneUpdatedOn(scene: scene)
    }

    private func updateUptime(now: ContinuousClock.Instant) {
        if let streamStartTime, isStreamConnected() {
            let elapsed = now - streamStartTime
            uptime = uptimeFormatter.string(from: Double(elapsed.components.seconds))!
        } else if uptime != noValue {
            uptime = noValue
        }
    }

    private func updateRecordingLength(now: Date) {
        if let currentRecording {
            let elapsed = uptimeFormatter.string(from: now.timeIntervalSince(currentRecording.startTime))!
            let size = currentRecording.url().fileSize.formatBytes()
            recordingLength = "\(elapsed) (\(size))"
            sendRecordingLengthToWatch()
        } else if recordingLength != noValue {
            recordingLength = noValue
            sendRecordingLengthToWatch()
        }
    }

    private func updateDigitalClock(now: Date) {
        let newDigitalClock = digitalClockFormatter.string(from: now)
        if digitalClock != newDigitalClock {
            digitalClock = newDigitalClock
        }
    }

    private func updateBatteryLevel() {
        batteryLevel = Double(UIDevice.current.batteryLevel)
        streamingHistoryStream?.updateLowestBatteryLevel(level: batteryLevel)
        if batteryLevel < 0.05 && !isBatteryCharging() && !ProcessInfo().isiOSAppOnMac {
            makeWarningToast(title: lowBatteryMessage, vibrate: true)
        }
    }

    private func updateBatteryState() {
        batteryState = UIDevice.current.batteryState
    }

    func isBatteryCharging() -> Bool {
        return batteryState == .charging || batteryState == .full
    }

    private func updateChatSpeed() {
        if numberOfChatPostsPerTick != 0 {
            chatPostsTotal += numberOfChatPostsPerTick
        }
        chatPostsRatePerSecond = chatPostsRatePerSecond * 0.8 +
            Double(numberOfChatPostsPerTick) * 0.2
        numberOfChatPostsPerMinute += numberOfChatPostsPerTick
        if chatSpeedTicks % 60 == 0 {
            chatPostsRatePerMinute = chatPostsRatePerMinute * 0.5 +
                Double(numberOfChatPostsPerMinute) * 0.5
            numberOfChatPostsPerMinute = 0
        }
        let newChatPostsRate: String
        if chatPostsRatePerSecond > 0.5 ||
            (chatPostsRatePerSecond > 0.05 && chatPostsRate.hasSuffix(secondsSuffix))
        {
            newChatPostsRate = String(format: "%.1f", chatPostsRatePerSecond) + secondsSuffix
        } else {
            newChatPostsRate = String(format: String(localized: "%.1f/min"), chatPostsRatePerMinute)
        }
        if chatPostsRate != newChatPostsRate {
            chatPostsRate = newChatPostsRate
        }
        numberOfChatPostsPerTick = 0
        chatSpeedTicks += 1
    }

    private func checkLowBitrate(speed: Int64, now: ContinuousClock.Instant) {
        guard database.lowBitrateWarning! else {
            return
        }
        guard streamState == .connected else {
            return
        }
        if speed < 500_000 && now > latestLowBitrateTime + .seconds(15) {
            makeWarningToast(title: lowBitrateMessage, vibrate: true)
            latestLowBitrateTime = now
        }
    }

    private func updateSpeed(now: ContinuousClock.Instant) {
        if isLive {
            let speed = media.streamSpeed()
            checkLowBitrate(speed: speed, now: now)
            streamingHistoryStream?.updateBitrate(bitrate: speed)
            let speedString = formatBytesPerSecond(speed: speed)
            let total = sizeFormatter.string(fromByteCount: media.streamTotal())
            speedAndTotal = String(localized: "\(speedString) (\(total))")
            sendSpeedAndTotalToWatch()
        } else if speedAndTotal != noValue {
            speedAndTotal = noValue
            sendSpeedAndTotalToWatch()
        }
    }

    private var serversSpeed: Int64 = 0

    private func updateServersSpeed() {
        var anyServerEnabled = false
        var speed: UInt64 = 0
        var total: UInt64 = 0
        var numberOfClients = 0
        if let rtmpServer {
            let stats = rtmpServer.updateStats()
            numberOfClients += rtmpServer.numberOfClients()
            if rtmpServer.numberOfClients() > 0 {
                total += stats.total
                speed += stats.speed
            }
            anyServerEnabled = true
        }
        if let srtlaServer {
            let stats = srtlaServer.updateStats()
            numberOfClients += srtlaServer.numberOfClients()
            if srtlaServer.numberOfClients() > 0 {
                total += stats.total
                speed += stats.speed
            }
            anyServerEnabled = true
        }
        let message: String
        if anyServerEnabled {
            if numberOfClients > 0 {
                let total = total.formatBytes()
                serversSpeed = Int64(Double(serversSpeed) * 0.7 + Double(speed) * 0.3)
                let speed = formatBytesPerSecond(speed: 8 * serversSpeed)
                message = String(localized: "\(speed) (\(total)) \(numberOfClients)")
            } else {
                message = String(numberOfClients)
            }
        } else {
            message = noValue
        }
        if message != serversSpeedAndTotal {
            serversSpeedAndTotal = message
        }
    }

    func rtmpServerEnabled() -> Bool {
        return rtmpServer != nil
    }

    func checkPhotoLibraryAuthorization() {
        PHPhotoLibrary
            .requestAuthorization(for: .readWrite) { authorizationStatus in
                switch authorizationStatus {
                case .limited:
                    logger.warning("photo-auth: limited authorization granted")
                case .authorized:
                    logger.info("photo-auth: authorization granted")
                default:
                    logger.error("photo-auth: Status \(authorizationStatus)")
                }
            }
    }

    private func setupThermalState() {
        updateThermalState()
        NotificationCenter.default.publisher(
            for: ProcessInfo.thermalStateDidChangeNotification,
            object: nil
        )
        .sink { _ in
            DispatchQueue.main.async {
                self.updateThermalState()
            }
        }
        .store(in: &subscriptions)
    }

    private func updateThermalState() {
        thermalState = ProcessInfo.processInfo.thermalState
        streamingHistoryStream?.updateHighestThermalState(thermalState: ThermalState(from: thermalState))
        sendThermalStateToWatch()
        logger.info("Thermal state is \(thermalState.string())")
    }

    func reattachCamera() {
        detachCamera()
        attachCamera()
    }

    func detachCamera() {
        media.attachCamera(device: nil, videoStabilizationMode: .off, videoMirrored: false)
    }

    func attachCamera() {
        lastAttachCompletedTime = nil
        let isMirrored = getVideoMirroredOnScreen()
        media.attachCamera(
            device: cameraDevice,
            videoStabilizationMode: getVideoStabilizationMode(),
            videoMirrored: getVideoMirroredOnStream()
        ) {
            self.streamPreviewView.isMirrored = isMirrored
            self.updateCameraPreview()
            self.lastAttachCompletedTime = .now
        }
    }

    private func updateCameraPreview() {
        updateCameraPreviewRotation()
    }

    private func updateCameraPreviewRotation() {}

    func setGlobalToneMapping(on: Bool) {
        guard let cameraDevice else {
            return
        }
        guard cameraDevice.activeFormat.isGlobalToneMappingSupported else {
            logger.info("Global tone mapping is not supported")
            return
        }
        do {
            try cameraDevice.lockForConfiguration()
            cameraDevice.isGlobalToneMappingEnabled = on
            cameraDevice.unlockForConfiguration()
        } catch {
            logger.info("Failed to set global tone mapping")
        }
    }

    func getGlobalToneMappingOn() -> Bool {
        return cameraDevice?.isGlobalToneMappingEnabled ?? false
    }

    private func getVideoMirroredOnStream() -> Bool {
        if cameraPosition == .front {
            if stream.portrait! {
                return true
            } else {
                return database.mirrorFrontCameraOnStream!
            }
        }
        return false
    }

    private func getVideoMirroredOnScreen() -> Bool {
        if cameraPosition == .front {
            if stream.portrait! {
                return false
            } else {
                return !database.mirrorFrontCameraOnStream!
            }
        }
        return false
    }

    private func hasCameraChanged(
        oldCameraDevice: AVCaptureDevice?,
        oldPosition: AVCaptureDevice.Position?,
        newPosition: AVCaptureDevice.Position?
    ) -> Bool {
        if oldPosition != newPosition {
            return true
        }
        if let newPosition {
            return oldCameraDevice != preferredCamera(position: newPosition)
        } else {
            return oldCameraDevice != nil
        }
    }

    private func attachCamera(position: AVCaptureDevice.Position) {
        guard hasCameraChanged(
            oldCameraDevice: cameraDevice,
            oldPosition: cameraPosition,
            newPosition: position
        ) else {
            media.usePendingAfterAttachEffects()
            return
        }
        cameraDevice = preferredCamera(position: position)
        setFocusAfterCameraAttach()
        cameraZoomLevelToXScale = cameraDevice?
            .getZoomFactorScale(hasUltraWideCamera: hasUltraWideBackCamera()) ?? 1.0
        (cameraZoomXMinimum, cameraZoomXMaximum) = cameraDevice?
            .getUIZoomRange(hasUltraWideCamera: hasUltraWideBackCamera()) ?? (
                1.0,
                1.0
            )
        cameraPosition = position
        switch position {
        case .back:
            if database.zoom.switchToBack.enabled {
                clearZoomId()
                backZoomX = database.zoom.switchToBack.x!
            }
            zoomX = backZoomX
        case .front:
            if database.zoom.switchToFront.enabled {
                clearZoomId()
                frontZoomX = database.zoom.switchToFront.x!
            }
            zoomX = frontZoomX
        default:
            break
        }
        lastAttachCompletedTime = nil
        let isMirrored = getVideoMirroredOnScreen()
        media.attachCamera(
            device: cameraDevice,
            videoStabilizationMode: getVideoStabilizationMode(),
            videoMirrored: getVideoMirroredOnStream(),
            onSuccess: {
                self.streamPreviewView.isMirrored = isMirrored
                if let x = self.setCameraZoomX(x: self.zoomX) {
                    self.setZoomX(x: x)
                }
                if let device = self.cameraDevice {
                    self.setIsoAfterCameraAttach(device: device)
                    self.setWhiteBalanceAfterCameraAttach(device: device)
                }
                self.updateCameraPreview()
                self.lastAttachCompletedTime = .now
            }
        )
        zoomXPinch = zoomX
        hasZoom = true
    }

    private func attachRtmpCamera(cameraId: UUID) {
        cameraDevice = nil
        cameraPosition = nil
        streamPreviewView.isMirrored = false
        hasZoom = false
        media.attachRtmpCamera(cameraId: cameraId, device: AVCaptureDevice(uniqueID: backCameras[0].id))
    }

    private func attachExternalCamera(cameraId _: String) {
        attachCamera(position: .unspecified)
    }

    private func setCameraZoomX(x: Float, rate: Float? = nil) -> Float? {
        let level = media.setCameraZoomLevel(level: x / cameraZoomLevelToXScale, rate: rate)
        if let level {
            return level * cameraZoomLevelToXScale
        }
        return level
    }

    private func stopCameraZoom() -> Float? {
        let level = media.stopCameraZoomLevel()
        if let level {
            return level * cameraZoomLevelToXScale
        }
        return level
    }

    func setExposureBias(bias: Float) {
        guard let position = cameraPosition else {
            return
        }
        guard let device = preferredCamera(position: position) else {
            return
        }
        if bias < device.minExposureTargetBias {
            return
        }
        if bias > device.maxExposureTargetBias {
            return
        }
        do {
            try device.lockForConfiguration()
            device.setExposureTargetBias(bias)
            device.unlockForConfiguration()
        } catch {}
    }

    private func getVideoStabilizationMode() -> AVCaptureVideoStabilizationMode {
        switch database.videoStabilizationMode {
        case .off:
            return .off
        case .standard:
            return .standard
        case .cinematic:
            return .cinematic
        }
    }

    func toggleTorch() {
        isTorchOn.toggle()
        updateTorch()
    }

    private func updateTorch() {
        media.setTorch(on: isTorchOn)
    }

    func toggleMute() {
        isMuteOn.toggle()
        updateMute()
    }

    private func updateMute() {
        media.setMute(on: isMuteOn)
        sendIsMutedToWatch()
    }

    func setCameraZoomPreset(id: UUID) {
        switch cameraPosition {
        case .back:
            backZoomPresetId = id
        case .front:
            frontZoomPresetId = id
        default:
            break
        }
        if let preset = findZoomPreset(id: id) {
            if setCameraZoomX(x: preset.x!, rate: database.zoom.speed!) != nil {
                setZoomX(x: preset.x!)
            }
        }
    }

    private func setZoomX(x: Float, setPinch: Bool = true) {
        switch cameraPosition {
        case .back:
            backZoomX = x
        case .front:
            frontZoomX = x
        default:
            break
        }
        zoomX = x
        remoteControlStreamer?.stateChanged(state: RemoteControlState(zoom: x))
        if setPinch {
            zoomXPinch = zoomX
        }
    }

    func changeZoomX(amount: Float, rate: Float? = nil) {
        guard hasZoom else {
            return
        }
        clearZoomId()
        if let x = setCameraZoomX(x: zoomXPinch * amount, rate: rate) {
            setZoomX(x: x, setPinch: false)
        }
    }

    func commitZoomX(amount: Float, rate: Float? = nil) {
        guard hasZoom else {
            return
        }
        clearZoomId()
        if let x = setCameraZoomX(x: zoomXPinch * amount, rate: rate) {
            setZoomX(x: x)
        }
    }

    private func clearZoomId() {
        switch cameraPosition {
        case .back:
            backZoomPresetId = UUID()
        case .front:
            frontZoomPresetId = UUID()
        default:
            break
        }
    }

    private func findZoomPreset(id: UUID) -> SettingsZoomPreset? {
        switch cameraPosition {
        case .back:
            return database.zoom.back.first { preset in
                preset.id == id
            }
        case .front:
            return database.zoom.front.first { preset in
                preset.id == id
            }
        default:
            return nil
        }
    }

    private func handleRtmpConnected() {
        onConnected()
    }

    private func handleRtmpDisconnected(message: String) {
        onDisconnected(reason: "RTMP disconnected with message \(message)")
    }

    private func handleRistConnected() {
        DispatchQueue.main.async {
            self.onConnected()
        }
    }

    private func handleRistDisconnected() {
        DispatchQueue.main.async {
            self.onDisconnected(reason: "RIST disconnected")
        }
    }

    private func handleLowFpsImage(image: Data?) {
        guard let image else {
            return
        }
        DispatchQueue.main.async {
            self.sendPreviewToWatch(image: image)
            self.sendPreviewToRemoteControlAssistant(preview: image)
        }
    }

    private func handleFindVideoFormatError(findVideoFormatError: String, activeFormat: String) {
        DispatchQueue.main.async {
            self.makeErrorToast(title: findVideoFormatError, subTitle: activeFormat)
        }
    }

    private func onConnected() {
        makeYouAreLiveToast()
        streamStartTime = .now
        streamState = .connected
        updateUptime(now: .now)
    }

    private func onDisconnected(reason: String) {
        guard streaming else {
            return
        }
        logger.info("stream: Disconnected with reason \(reason)")
        let subTitle = String(localized: "Attempting again in 5 seconds.")
        if streamState == .connected {
            streamTotalBytes += UInt64(media.streamTotal())
            streamingHistoryStream?.numberOfFffffs! += 1
            makeFffffToast(subTitle: subTitle)
        } else if streamState == .connecting {
            makeConnectFailureToast(subTitle: subTitle)
        }
        streamState = .disconnected
        stopNetStream(reconnect: true)
        reconnectTimer = Timer
            .scheduledTimer(withTimeInterval: 5, repeats: false) { _ in
                logger.info("stream: Reconnecting")
                self.startNetStream(reconnect: true)
            }
    }

    private func handleSrtConnected() {
        onConnected()
    }

    private func handleSrtDisconnected(reason: String) {
        onDisconnected(reason: reason)
    }

    func backZoomUpdated() {
        if !database.zoom.back.contains(where: { level in
            level.id == backZoomPresetId
        }) {
            backZoomPresetId = database.zoom.back[0].id
        }
        sceneUpdated(store: true)
    }

    func frontZoomUpdated() {
        if !database.zoom.front.contains(where: { level in
            level.id == frontZoomPresetId
        }) {
            frontZoomPresetId = database.zoom.front[0].id
        }
        sceneUpdated(store: true)
    }

    private func makeConnectFailureToast(subTitle: String) {
        makeErrorToast(title: failedToConnectMessage(stream.name),
                       subTitle: subTitle,
                       vibrate: true)
    }

    private func makeYouAreLiveToast() {
        makeToast(title: String(localized: "🎉 You are LIVE at \(stream.name) 🎉"))
    }

    private func makeStreamEndedToast() {
        makeToast(title: String(localized: "🤟 Stream ended 🤟"))
    }

    private func makeFffffToast(subTitle: String) {
        makeErrorToast(
            title: String(localized: "😢 FFFFF 😢"),
            font: .system(size: 64).bold(),
            subTitle: subTitle,
            vibrate: true
        )
    }

    private func startMotionDetection() {
        motionManager.stopDeviceMotionUpdates()
        manualFocusMotionAttitude = nil
        motionManager.deviceMotionUpdateInterval = 0.2
        motionManager.startDeviceMotionUpdates(to: OperationQueue.main) { data, _ in
            guard let data else {
                return
            }
            let attitude = data.attitude
            if self.manualFocusMotionAttitude == nil {
                self.manualFocusMotionAttitude = attitude
            }
            if diffAngles(attitude.pitch, self.manualFocusMotionAttitude!.pitch) > 10 {
                self.setAutoFocus()
            } else if diffAngles(attitude.roll, self.manualFocusMotionAttitude!.roll) > 10 {
                self.setAutoFocus()
            } else if diffAngles(attitude.yaw, self.manualFocusMotionAttitude!.yaw) > 10 {
                self.setAutoFocus()
            }
        }
    }

    private func stopMotionDetection() {
        motionManager.stopDeviceMotionUpdates()
    }

    func preferredCamera(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        if let scene = findEnabledScene(id: selectedSceneId) {
            if position == .back {
                return AVCaptureDevice(uniqueID: scene.backCameraId!)
            } else if position == .front {
                return AVCaptureDevice(uniqueID: scene.frontCameraId!)
            } else {
                return AVCaptureDevice(uniqueID: scene.externalCameraId!)
            }
        } else {
            return nil
        }
    }

    private func factorToX(position: AVCaptureDevice.Position, factor: Float) -> Float {
        if position == .back && hasUltraWideBackCamera() {
            return factor / 2
        }
        return factor
    }

    func getMinMaxZoomX(position: AVCaptureDevice.Position) -> (Float, Float) {
        var minX: Float
        var maxX: Float
        if let device = preferredCamera(position: position) {
            minX = factorToX(
                position: position,
                factor: Float(device.minAvailableVideoZoomFactor)
            )
            maxX = factorToX(
                position: position,
                factor: Float(device.maxAvailableVideoZoomFactor)
            )
        } else {
            minX = 1.0
            maxX = 1.0
        }
        return (minX, maxX)
    }

    func isShowingStatusStream() -> Bool {
        return database.show.stream && isStreamConfigured()
    }

    func isShowingStatusCamera() -> Bool {
        return database.show.cameras!
    }

    func isShowingStatusMic() -> Bool {
        return database.show.microphone
    }

    func isShowingStatusZoom() -> Bool {
        return database.show.zoom && hasZoom
    }

    func isShowingStatusObs() -> Bool {
        return database.show.obsStatus! && isObsRemoteControlConfigured()
    }

    func isShowingStatusChat() -> Bool {
        return database.show.chat && isChatConfigured()
    }

    func isShowingStatusViewers() -> Bool {
        return database.show.viewers && isViewersConfigured()
    }

    func statusStreamText() -> String {
        let proto = stream.protocolString()
        let resolution = stream.resolutionString()
        let codec = stream.codecString()
        let bitrate = stream.bitrateString()
        let audioCodec = stream.audioCodecString()
        let audioBitrate = stream.audioBitrateString()
        return """
        \(stream.name) (\(resolution), \(stream.fps), \(proto), \(codec) \(bitrate), \
        \(audioCodec) \(audioBitrate))
        """
    }

    func statusCameraText() -> String {
        return getCameraPositionName(scene: findEnabledScene(id: selectedSceneId))
    }

    func statusZoomText() -> String {
        return String(format: "%.1f", zoomX)
    }

    func statusObsText() -> String {
        if !isObsRemoteControlConfigured() {
            return String(localized: "Not configured")
        } else if isObsConnected() {
            if obsStreaming && obsRecording {
                return "\(obsCurrentScene) (Streaming, Recording)"
            } else if obsStreaming {
                return "\(obsCurrentScene) (Streaming)"
            } else if obsRecording {
                return "\(obsCurrentScene) (Recording)"
            } else {
                return obsCurrentScene
            }
        } else {
            return obsConnectionErrorMessage()
        }
    }

    func statusChatText() -> String {
        if !isChatConfigured() {
            return String(localized: "Not configured")
        } else if isChatConnected() {
            return String(
                format: String(localized: "%@ (%@ total)"),
                chatPostsRate,
                countFormatter.format(chatPostsTotal)
            )
        } else {
            return String(localized: "Disconnected")
        }
    }

    func statusViewersText() -> String {
        if isViewersConfigured() {
            return numberOfViewers
        } else {
            return String(localized: "Not configured")
        }
    }

    func isShowingStatusAudioLevel() -> Bool {
        return database.show.audioLevel
    }

    func isShowingStatusServers() -> Bool {
        return database.show.rtmpSpeed! && (rtmpServerEnabled() || srtlaServerEnabled())
    }

    func isShowingStatusRemoteControl() -> Bool {
        return database.show
            .remoteControl! && (isRemoteControlStreamerConfigured() || isRemoteControlAssistantConfigured())
    }

    func isShowingStatusGameController() -> Bool {
        return database.show.gameController! && isGameControllerConnected()
    }

    func isShowingStatusBitrate() -> Bool {
        return database.show.speed && isLive
    }

    func isShowingStatusUptime() -> Bool {
        return database.show.uptime && isLive
    }

    func isShowingStatusLocation() -> Bool {
        return database.show.location! && isLocationEnabled()
    }

    func isShowingStatusBonding() -> Bool {
        return database.show.bonding! && stream.isBonding() && isLive
    }

    func isShowingStatusRecording() -> Bool {
        return isRecording
    }

    func isShowingStatusBrowserWidgets() -> Bool {
        return database.show.browserWidgets! && !browserWidgetsStatus
            .isEmpty && browserWidgetsStatusChanged
    }
}

extension Model: RemoteControlStreamerDelegate {
    func connected() {
        DispatchQueue.main.async {
            self.makeToast(title: "Remote control assistant connected")
            self.setLowFpsImage()
            self.updateRemoteControlStatus()
            var state = RemoteControlState()
            if self.sceneIndex < self.enabledScenes.count {
                state.scene = self.enabledScenes[self.sceneIndex].id
            }
            state.mic = self.currentMic.id
            if let preset = self.getBitratePresetByBitrate(bitrate: self.stream.bitrate) {
                state.bitrate = preset.id
            }
            state.zoom = self.zoomX
            self.remoteControlStreamer?.stateChanged(state: state)
        }
    }

    func disconnected() {
        DispatchQueue.main.async {
            self.makeToast(title: "Remote control assistant disconnected")
            self.setLowFpsImage()
            self.updateRemoteControlStatus()
        }
    }

    func getStatus(onComplete: @escaping (
        RemoteControlStatusGeneral,
        RemoteControlStatusTopLeft,
        RemoteControlStatusTopRight
    ) -> Void) {
        DispatchQueue.main.async {
            var general = RemoteControlStatusGeneral()
            general.batteryCharging = self.isBatteryCharging()
            general.batteryLevel = Int(100 * self.batteryLevel)
            switch self.thermalState {
            case .nominal:
                general.flame = .white
            case .fair:
                general.flame = .white
            case .serious:
                general.flame = .yellow
            case .critical:
                general.flame = .red
            @unknown default:
                general.flame = .red
            }
            general.wiFiSsid = self.currentWiFiSsid
            var topLeft = RemoteControlStatusTopLeft()
            if self.isShowingStatusStream() {
                topLeft.stream = RemoteControlStatusItem(message: self.statusStreamText())
            }
            if self.isShowingStatusCamera() {
                topLeft.camera = RemoteControlStatusItem(message: self.statusCameraText())
            }
            if self.isShowingStatusMic() {
                topLeft.mic = RemoteControlStatusItem(message: self.currentMic.name)
            }
            if self.isShowingStatusZoom() {
                topLeft.zoom = RemoteControlStatusItem(message: self.statusZoomText())
            }
            if self.isShowingStatusObs() {
                topLeft.obs = RemoteControlStatusItem(message: self.statusObsText())
            }
            if self.isShowingStatusChat() {
                topLeft.chat = RemoteControlStatusItem(message: self.statusChatText())
            }
            if self.isShowingStatusViewers() {
                topLeft.viewers = RemoteControlStatusItem(message: self.statusViewersText())
            }
            var topRight = RemoteControlStatusTopRight()
            if self.isShowingStatusAudioLevel() {
                let level = formatAudioLevel(level: self.audioLevel) +
                    formatAudioLevelChannels(channels: self.numberOfAudioChannels)
                topRight.audioLevel = RemoteControlStatusItem(message: level)
            }
            if self.isShowingStatusServers() {
                topRight.rtmpServer = RemoteControlStatusItem(message: self.serversSpeedAndTotal)
            }
            if self.isShowingStatusRemoteControl() {
                topRight.remoteControl = RemoteControlStatusItem(message: self.remoteControlStatus)
            }
            if self.isShowingStatusGameController() {
                topRight.gameController = RemoteControlStatusItem(message: self.gameControllersTotal)
            }
            if self.isShowingStatusBitrate() {
                topRight.bitrate = RemoteControlStatusItem(message: self.speedAndTotal)
            }
            if self.isShowingStatusUptime() {
                topRight.uptime = RemoteControlStatusItem(message: self.uptime)
            }
            if self.isShowingStatusLocation() {
                topRight.location = RemoteControlStatusItem(message: self.location)
            }
            if self.isShowingStatusBonding() {
                topRight.srtla = RemoteControlStatusItem(message: self.bondingStatistics)
            }
            if self.isShowingStatusRecording() {
                topRight.recording = RemoteControlStatusItem(message: self.recordingLength)
            }
            if self.isShowingStatusBrowserWidgets() {
                topRight.browserWidgets = RemoteControlStatusItem(message: self.browserWidgetsStatus)
            }
            onComplete(general, topLeft, topRight)
        }
    }

    func getSettings(onComplete: @escaping (RemoteControlSettings) -> Void) {
        DispatchQueue.main.async {
            let scenes = self.database.scenes.map { scene in
                RemoteControlSettingsScene(id: scene.id, name: scene.name)
            }
            let mics = self.listMics().map { mic in
                RemoteControlSettingsMic(id: mic.id, name: mic.name)
            }
            let bitratePresets = self.database.bitratePresets.map { preset in
                RemoteControlSettingsBitratePreset(id: preset.id, bitrate: preset.bitrate)
            }
            let connectionPriorities = self.stream.srt.connectionPriorities!.priorities
                .map { priority in
                    RemoteControlSettingsSrtConnectionPriority(
                        id: priority.id,
                        name: priority.name,
                        priority: priority.priority,
                        enabled: priority.enabled!
                    )
                }
            let connectionPrioritiesEnabled = self.stream.srt.connectionPriorities!.enabled
            onComplete(RemoteControlSettings(
                scenes: scenes,
                bitratePresets: bitratePresets,
                mics: mics,
                srt: RemoteControlSettingsSrt(
                    connectionPrioritiesEnabled: connectionPrioritiesEnabled,
                    connectionPriorities: connectionPriorities
                )
            ))
        }
    }

    func setScene(id: UUID, onComplete: @escaping () -> Void) {
        DispatchQueue.main.async {
            self.selectScene(id: id)
            onComplete()
        }
    }

    func setMic(id: String, onComplete: @escaping () -> Void) {
        DispatchQueue.main.async {
            self.selectMicById(id: id)
            onComplete()
        }
    }

    func setBitratePreset(id: UUID, onComplete: @escaping () -> Void) {
        DispatchQueue.main.async {
            guard let preset = self.database.bitratePresets.first(where: { preset in
                preset.id == id
            }) else {
                return
            }
            self.setBitrate(bitrate: preset.bitrate)
            if self.stream.enabled {
                self.setStreamBitrate(stream: self.stream)
            }
            onComplete()
        }
    }

    func setRecord(on: Bool, onComplete: @escaping () -> Void) {
        DispatchQueue.main.async {
            if on {
                self.startRecording()
            } else {
                self.stopRecording()
            }
            self.updateButtonStates()
            onComplete()
        }
    }

    func setStream(on: Bool, onComplete: @escaping () -> Void) {
        DispatchQueue.main.async {
            if on {
                self.startStream()
            } else {
                self.stopStream()
            }
            self.updateButtonStates()
            onComplete()
        }
    }

    func setZoom(x: Float, onComplete: @escaping () -> Void) {
        DispatchQueue.main.async {
            if let x = self.setCameraZoomX(x: x, rate: self.database.zoom.speed!) {
                self.setZoomX(x: x)
            }
            onComplete()
        }
    }

    private func setMuteOn(value: Bool) {
        if value {
            isMuteOn = true
        } else {
            isMuteOn = false
        }
        updateMute()
        setGlobalButtonState(type: .mute, isOn: value)
        updateButtonStates()
    }

    func setMute(on: Bool, onComplete: @escaping () -> Void) {
        DispatchQueue.main.async {
            self.setMuteOn(value: on)
            onComplete()
        }
    }

    func setTorch(on: Bool, onComplete: @escaping () -> Void) {
        DispatchQueue.main.async {
            if on {
                self.isTorchOn = true
            } else {
                self.isTorchOn = false
            }
            self.updateTorch()
            self.toggleGlobalButton(type: .torch)
            self.updateButtonStates()
            onComplete()
        }
    }

    func reloadBrowserWidgets(onComplete: @escaping () -> Void) {
        DispatchQueue.main.async {
            self.reloadBrowserWidgets()
            onComplete()
        }
    }

    func setSrtConnectionPrioritiesEnabled(enabled: Bool, onComplete: @escaping () -> Void) {
        DispatchQueue.main.async {
            self.stream.srt.connectionPriorities!.enabled = enabled
            self.store()
            self.updateSrtlaPriorities()
            onComplete()
        }
    }

    func setSrtConnectionPriority(id: UUID, priority: Int, enabled: Bool, onComplete: @escaping () -> Void) {
        DispatchQueue.main.async {
            if let entry = self.stream.srt.connectionPriorities!.priorities.first(where: { $0.id == id }) {
                entry.priority = clampConnectionPriority(value: priority)
                entry.enabled = enabled
                self.store()
                self.updateSrtlaPriorities()
            }
            onComplete()
        }
    }

    private func sendPreviewToRemoteControlAssistant(preview: Data) {
        guard isRemoteControlStreamerConnected() else {
            return
        }
        remoteControlStreamer?.sendPreview(preview: preview)
    }
}

extension Model {
    func isObsRemoteControlConfigured() -> Bool {
        return stream.obsWebSocketEnabled! && stream.obsWebSocketUrl != "" && stream
            .obsWebSocketPassword != ""
    }

    func clearRemoteControlAssistantLog() {
        remoteControlAssistantLog = []
    }

    func reloadRemoteControlStreamer() {
        remoteControlStreamer?.stop()
        remoteControlStreamer = nil
        guard isRemoteControlStreamerConfigured() else {
            return
        }
        let server = database.remoteControl!.server
        guard let url = URL(string: server.url) else {
            return
        }
        remoteControlStreamer = RemoteControlStreamer(
            clientUrl: url,
            password: database.remoteControl!.password!,
            delegate: self
        )
        remoteControlStreamer!.start()
    }

    private func updateRemoteControlStatus() {
        if isRemoteControlAssistantConnected(), isRemoteControlStreamerConnected() {
            remoteControlStatus = String(localized: "Assistant and streamer")
        } else if isRemoteControlAssistantConnected() {
            remoteControlStatus = String(localized: "Assistant")
        } else if isRemoteControlStreamerConnected() {
            remoteControlStatus = String(localized: "Streamer")
        } else {
            let assistantError = remoteControlAssistant?.connectionErrorMessage ?? ""
            let streamerError = remoteControlStreamer?.connectionErrorMessage ?? ""
            if isRemoteControlAssistantConfigured(), isRemoteControlStreamerConfigured() {
                remoteControlStatus = "\(assistantError), \(streamerError)"
            } else if isRemoteControlAssistantConfigured() {
                remoteControlStatus = assistantError
            } else if isRemoteControlStreamerConfigured() {
                remoteControlStatus = streamerError
            } else {
                remoteControlStatus = noValue
            }
        }
    }

    func isRemoteControlStreamerConfigured() -> Bool {
        let server = database.remoteControl!.server
        return server.enabled && !server.url.isEmpty && !database.remoteControl!.password!.isEmpty
    }

    func isRemoteControlStreamerConnected() -> Bool {
        return remoteControlStreamer?.isConnected() ?? false
    }

    func reloadRemoteControlAssistant() {
        remoteControlAssistant?.stop()
        remoteControlAssistant = nil
        guard isRemoteControlAssistantConfigured() else {
            return
        }
        let client = database.remoteControl!.client
        remoteControlAssistant = RemoteControlAssistant(
            port: client.port,
            password: database.remoteControl!.password!,
            delegate: self
        )
        remoteControlAssistant!.start()
    }

    func isRemoteControlAssistantConnected() -> Bool {
        return remoteControlAssistant?.isConnected() ?? false
    }

    func updateRemoteControlAssistantStatus() {
        guard showingRemoteControl, remoteControlAssistant?.isConnected() == true else {
            return
        }
        remoteControlAssistant?.getStatus { general, topLeft, topRight in
            self.remoteControlGeneral = general
            self.remoteControlTopLeft = topLeft
            self.remoteControlTopRight = topRight
        }
        remoteControlAssistant?.getSettings { settings in
            self.remoteControlSettings = settings
        }
    }

    func isRemoteControlAssistantConfigured() -> Bool {
        let client = database.remoteControl!.client
        return client.enabled && client.port > 0 && !database.remoteControl!.password!.isEmpty
    }

    func remoteControlAssistantSetScene(id: UUID) {
        remoteControlAssistant?.setScene(id: id) {}
    }

    func remoteControlAssistantSetMic(id: String) {
        remoteControlAssistant?.setMic(id: id) {}
    }

    func remoteControlAssistantSetZoom(x: Float) {
        remoteControlAssistant?.setZoom(x: x) {}
    }

    func remoteControlAssistantSetBitratePreset(id: UUID) {
        remoteControlAssistant?.setBitratePreset(id: id) {}
    }

    func remoteControlAssistantReloadBrowserWidgets() {
        remoteControlAssistant?.reloadBrowserWidgets {
            DispatchQueue.main.async {
                self.makeToast(title: "Browser widgets reloaded")
            }
        }
    }

    func remoteControlAssistantSetSrtConnectionPriorityEnabled(enabled: Bool) {
        remoteControlAssistant?.setSrtConnectionPrioritiesEnabled(
            enabled: enabled
        ) {}
    }

    func remoteControlAssistantSetSrtConnectionPriority(priority: RemoteControlSettingsSrtConnectionPriority) {
        remoteControlAssistant?.setSrtConnectionPriority(
            id: priority.id,
            priority: priority.priority,
            enabled: priority.enabled
        ) {}
    }
}

extension Model: RemoteControlAssistantDelegate {
    func assistantConnected() {
        makeToast(title: "Remote control streamer connected")
        updateRemoteControlStatus()
        updateRemoteControlAssistantStatus()
    }

    func assistantDisconnected() {
        makeToast(title: "Remote control streamer disconnected")
        remoteControlTopLeft = nil
        remoteControlTopRight = nil
        updateRemoteControlStatus()
    }

    func assistantStateChanged(state: RemoteControlState) {
        if let scene = state.scene {
            remoteControlState.scene = scene
            remoteControlScene = scene
        }
        if let mic = state.mic {
            remoteControlState.mic = mic
            remoteControlMic = mic
        }
        if let bitrate = state.bitrate {
            remoteControlState.bitrate = bitrate
            remoteControlBitrate = bitrate
        }
        if let zoom = state.zoom {
            remoteControlState.zoom = zoom
            remoteControlZoom = String(zoom)
        }
    }

    func assistantPreview(preview: Data) {
        remoteControlPreview = UIImage(data: preview)
    }

    func assistantLog(entry: String) {
        if remoteControlAssistantLog.count > 100_000 {
            remoteControlAssistantLog.removeFirst()
        }
        logId += 1
        remoteControlAssistantLog.append(LogEntry(id: logId, message: entry))
    }
}

extension Model {
    private func isWatchReachable() -> Bool {
        return WCSession.default.activationState == .activated && WCSession.default.isReachable
    }

    private func sendMessageToWatch(
        type: WatchMessageToWatch,
        data: Any,
        replyHandler: (([String: Any]) -> Void)? = nil,
        errorHandler: ((Error) -> Void)? = nil
    ) {
        WCSession.default.sendMessage(
            WatchMessageToWatch.pack(type: type, data: data),
            replyHandler: replyHandler,
            errorHandler: errorHandler
        )
    }

    private func sendSpeedAndTotalToWatch() {
        guard isWatchReachable() else {
            return
        }
        sendMessageToWatch(type: .speedAndTotal, data: speedAndTotal)
    }

    private func sendRecordingLengthToWatch() {
        guard isWatchReachable() else {
            return
        }
        sendMessageToWatch(type: .recordingLength, data: recordingLength)
    }

    private func sendAudioLevelToWatch() {
        guard isWatchReachable() else {
            return
        }
        sendMessageToWatch(type: .audioLevel, data: audioLevel)
    }

    private func sendThermalStateToWatch() {
        guard isWatchReachable() else {
            return
        }
        sendMessageToWatch(type: .thermalState, data: thermalState)
    }

    private func enqueueWatchChatPost(post: ChatPost) {
        guard WCSession.default.isWatchAppInstalled else {
            return
        }
        guard let user = post.user else {
            return
        }
        var userColor: WatchProtocolColor
        if let hexColor = post.userColor,
           let color = WatchProtocolColor.fromHex(value: hexColor)
        {
            userColor = color
        } else {
            let color = database.chat.usernameColor
            userColor = WatchProtocolColor(red: color.red, green: color.green, blue: color.blue)
        }
        let post = WatchProtocolChatMessage(
            id: nextWatchChatPostId,
            timestamp: post.timestamp,
            user: user,
            userColor: userColor,
            segments: post.segments
                .map { WatchProtocolChatSegment(text: $0.text, url: $0.url?.absoluteString) }
        )
        nextWatchChatPostId += 1
        watchChatPosts.append(post)
        if watchChatPosts.count > maximumNumberOfWatchChatMessages {
            _ = watchChatPosts.popFirst()
        }
    }

    private func trySendNextChatPostToWatch() {
        guard isWatchReachable(), let post = watchChatPosts.popFirst() else {
            return
        }
        var data: Data
        do {
            data = try JSONEncoder().encode(post)
        } catch {
            logger.info("watch: Chat message send failed")
            return
        }
        sendMessageToWatch(type: .chatMessage, data: data)
    }

    private func sendChatMessageToWatch(post: ChatPost) {
        enqueueWatchChatPost(post: post)
    }

    private func sendPreviewToWatch(image: Data) {
        guard isWatchReachable() else {
            return
        }
        sendMessageToWatch(type: .preview, data: image)
    }

    private func sendSettingsToWatch() {
        guard isWatchReachable() else {
            return
        }
        do {
            let settings = try JSONEncoder().encode(database.watch)
            sendMessageToWatch(type: .settings, data: settings)
        } catch {}
    }

    private func sendIsLiveToWatch() {
        guard isWatchReachable() else {
            return
        }
        sendMessageToWatch(type: .isLive, data: isLive)
    }

    private func sendIsRecordingToWatch() {
        guard isWatchReachable() else {
            return
        }
        sendMessageToWatch(type: .isRecording, data: isRecording)
    }

    private func sendIsMutedToWatch() {
        guard isWatchReachable() else {
            return
        }
        sendMessageToWatch(type: .isMuted, data: isMuteOn)
    }
}

extension Model: WCSessionDelegate {
    func session(
        _: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error _: Error?
    ) {
        logger.debug("watch: \(activationState)")
        switch activationState {
        case .activated:
            DispatchQueue.main.async {
                self.setLowFpsImage()
            }
        default:
            break
        }
    }

    func sessionDidBecomeInactive(_: WCSession) {
        logger.debug("watch: Session inactive")
    }

    func sessionDidDeactivate(_: WCSession) {
        logger.debug("watch: Session deactive")
    }

    func sessionReachabilityDidChange(_: WCSession) {
        logger.debug("watch: Reachability changed to \(isWatchReachable())")
        DispatchQueue.main.async {
            self.setLowFpsImage()
            self.trySendNextChatPostToWatch()
            self.sendSettingsToWatch()
            self.sendAudioLevelToWatch()
            self.sendThermalStateToWatch()
            self.sendIsLiveToWatch()
            self.sendIsRecordingToWatch()
            self.sendIsMutedToWatch()
        }
    }

    private func makePng(_ uiImage: UIImage) -> Data {
        for height in [35.0, 25.0, 15.0] {
            guard let pngData = uiImage.resize(height: height).pngData() else {
                return Data()
            }
            if pngData.count < 15000 {
                return pngData
            }
        }
        return Data()
    }

    private func handleGetImage(_ data: Any, _ replyHandler: @escaping ([String: Any]) -> Void) {
        guard let urlString = data as? String else {
            replyHandler(["data": Data()])
            return
        }
        guard let url = URL(string: urlString) else {
            replyHandler(["data": Data()])
            return
        }
        URLSession.shared.dataTask(with: URLRequest(url: url)) { data, response, _ in
            guard let response = response?.http else {
                replyHandler(["data": Data()])
                return
            }
            guard response.isSuccessful, let data else {
                replyHandler(["data": Data()])
                return
            }
            guard let uiImage = UIImage(data: data) else {
                replyHandler(["data": Data()])
                return
            }
            replyHandler(["data": self.makePng(uiImage)])
        }
        .resume()
    }

    private func handleSetIsLive(_ data: Any) {
        guard let value = data as? Bool else {
            return
        }
        DispatchQueue.main.async {
            if value {
                self.startStream()
            } else {
                self.stopStream()
            }
        }
    }

    private func handleSetIsRecording(_ data: Any) {
        guard let value = data as? Bool else {
            return
        }
        DispatchQueue.main.async {
            if value {
                self.startRecording()
            } else {
                self.stopRecording()
            }
        }
    }

    private func handleSetIsMuted(_ data: Any) {
        guard let value = data as? Bool else {
            return
        }
        DispatchQueue.main.async {
            self.setIsMuted(value: value)
        }
    }

    private func handleSkipCurrentChatTextToSpeechMessage(_: Any) {
        DispatchQueue.main.async {
            self.chatTextToSpeech.skipCurrentMessage()
        }
    }

    func session(
        _: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        guard let (type, data) = WatchMessageFromWatch.unpack(message) else {
            logger.info("watch: Invalid message")
            replyHandler([:])
            return
        }
        switch type {
        case .getImage:
            handleGetImage(data, replyHandler)
        default:
            replyHandler([:])
        }
    }

    func session(_: WCSession, didReceiveMessage message: [String: Any]) {
        guard let (type, data) = WatchMessageFromWatch.unpack(message) else {
            logger.info("watch: Invalid message")
            return
        }
        switch type {
        case .setIsLive:
            handleSetIsLive(data)
        case .setIsRecording:
            handleSetIsRecording(data)
        case .setIsMuted:
            handleSetIsMuted(data)
        case .keepAlive:
            break
        case .skipCurrentChatTextToSpeechMessage:
            handleSkipCurrentChatTextToSpeechMessage(data)
        default:
            break
        }
    }
}

extension Model {
    private func cleanWizardUrl(url: String) -> String {
        var cleanedUrl = cleanUrl(url: url)
        if isValidUrl(url: cleanedUrl) != nil {
            cleanedUrl = defaultStreamUrl
            makeErrorToast(title: "Malformed stream URL", subTitle: "Using default")
        }
        return cleanedUrl
    }

    private func createStreamFromWizardCustomUrl() -> String? {
        switch wizardCustomProtocol {
        case .none:
            break
        case .srt:
            if var urlComponents = URLComponents(string: wizardCustomSrtUrl.trim()) {
                urlComponents.queryItems = [
                    URLQueryItem(name: "streamid", value: wizardCustomSrtStreamId.trim()),
                ]
                if let fullUrl = urlComponents.url {
                    return fullUrl.absoluteString
                }
            }
        case .rtmp:
            let rtmpUrl = wizardCustomRtmpUrl
                .trim()
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return "\(rtmpUrl)/\(wizardCustomRtmpStreamKey.trim())"
        case .rist:
            return wizardCustomRistUrl.trim()
        }
        return nil
    }

    private func createStreamFromWizardUrl() -> String {
        var url = defaultStreamUrl
        if wizardPlatform == .custom {
            if let customUrl = createStreamFromWizardCustomUrl() {
                url = customUrl
            }
        } else {
            switch wizardNetworkSetup {
            case .none:
                break
            case .obs:
                url = "srt://\(wizardObsAddress):\(wizardObsPort)"
            case .belaboxCloudObs:
                url = wizardBelaboxUrl
            case .irlToolkit:
                let ingestUrl = wizardDirectIngest.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                if let directUrl = URL(string: "\(ingestUrl)/\(wizardDirectStreamKey)") {
                    url = "irltk:///?url=\(directUrl)"
                }
            case .direct:
                let ingestUrl = wizardDirectIngest.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                url = "\(ingestUrl)/\(wizardDirectStreamKey)"
            case .myServers:
                if let customUrl = createStreamFromWizardCustomUrl() {
                    url = customUrl
                }
            }
        }
        return cleanWizardUrl(url: url)
    }

    func createStreamFromWizard() {
        let stream = SettingsStream(name: wizardName.trim())
        stream.twitchEnabled = false
        stream.kickEnabled = false
        stream.youTubeEnabled = false
        stream.afreecaTvEnabled = false
        stream.openStreamingPlatformEnabled = false
        stream.obsWebSocketEnabled = false
        if wizardPlatform != .custom {
            if wizardNetworkSetup != .direct {
                if wizardObsRemoteControlEnabled {
                    let url = cleanUrl(url: wizardObsRemoteControlUrl.trim())
                    if isValidWebSocketUrl(url: url) == nil {
                        stream.obsWebSocketEnabled = true
                        stream.obsWebSocketUrl = url
                        stream.obsWebSocketPassword = wizardObsRemoteControlPassword.trim()
                        stream.obsSourceName = wizardObsRemoteControlSourceName.trim()
                    }
                }
            }
        }
        switch wizardPlatform {
        case .twitch:
            stream.twitchEnabled = true
            stream.twitchChannelName = wizardTwitchChannelName.trim()
            stream.twitchChannelId = wizardTwitchChannelId.trim()
        case .kick:
            stream.kickEnabled = true
            stream.kickChannelName = wizardKickChannelName.trim()
        case .youTube:
            if !wizardYouTubeVideoId.isEmpty {
                stream.youTubeEnabled = true
                stream.youTubeVideoId = wizardYouTubeVideoId.trim()
            }
        case .afreecaTv:
            if !wizardAfreecaTvChannelName.isEmpty, !wizardAfreecsTvCStreamId.isEmpty {
                stream.afreecaTvEnabled = true
                stream.afreecaTvChannelName = wizardAfreecaTvChannelName.trim()
                stream.afreecaTvStreamId = wizardAfreecsTvCStreamId.trim()
            }
        case .custom:
            break
        }
        stream.chat!.bttvEmotes = wizardChatBttv
        stream.chat!.ffzEmotes = wizardChatFfz
        stream.chat!.seventvEmotes = wizardChatSeventv
        stream.url = createStreamFromWizardUrl()
        switch wizardNetworkSetup {
        case .none:
            stream.codec = wizardCustomProtocol.toDefaultCodec()
        case .obs:
            stream.codec = .h265hevc
        case .belaboxCloudObs:
            stream.codec = .h265hevc
        case .irlToolkit:
            stream.codec = .h265hevc
        case .direct:
            stream.codec = .h264avc
        case .myServers:
            stream.codec = wizardCustomProtocol.toDefaultCodec()
        }
        stream.audioBitrate = 128_000
        database.streams.append(stream)
        setCurrentStream(stream: stream)
        reloadStream()
        sceneUpdated()
    }

    func resetWizard() {
        wizardPlatform = .custom
        wizardNetworkSetup = .none
        wizardName = ""
        wizardTwitchChannelName = ""
        wizardTwitchChannelId = ""
        wizardKickChannelName = ""
        wizardYouTubeVideoId = ""
        wizardAfreecaTvChannelName = ""
        wizardAfreecsTvCStreamId = ""
        wizardObsAddress = ""
        wizardObsPort = ""
        wizardObsRemoteControlEnabled = false
        wizardObsRemoteControlUrl = ""
        wizardObsRemoteControlPassword = ""
        wizardDirectIngest = ""
        wizardDirectStreamKey = ""
        wizardChatBttv = true
        wizardChatFfz = true
        wizardChatSeventv = true
        wizardBelaboxUrl = ""
    }

    private func handleSettingsUrlsInWizard(settings: MoblinSettingsUrl) {
        switch wizardNetworkSetup {
        case .none:
            break
        case .obs:
            break
        case .belaboxCloudObs:
            for stream in settings.streams ?? [] {
                wizardName = stream.name
                wizardBelaboxUrl = stream.url
            }
        case .irlToolkit:
            break
        case .direct:
            break
        case .myServers:
            break
        }
    }
}

extension Model {
    private func setupAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            let bluetoothOption: AVAudioSession.CategoryOptions
            if database.debug!.bluetoothOutputOnly! {
                bluetoothOption = .allowBluetoothA2DP
            } else {
                bluetoothOption = .allowBluetooth
            }
            try session.setCategory(
                .playAndRecord,
                options: [.mixWithOthers, bluetoothOption, .defaultToSpeaker]
            )
            try session.setActive(true)
        } catch {
            logger.error("app: Session error \(error)")
        }
        setAllowHapticsAndSystemSoundsDuringRecording()
    }

    private func teardownAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(false)
        } catch {
            logger.info("Failed to stop audio session with error: \(error)")
        }
    }

    @objc func handleAudioRouteChange(notification _: Notification) {
        guard let inputPort = AVAudioSession.sharedInstance().currentRoute.inputs.first
        else {
            return
        }
        var newMic: Mic
        if let dataSource = inputPort.preferredDataSource {
            var name: String
            var builtInMicOrientation: SettingsMic?
            if inputPort.portType == .builtInMic {
                name = dataSource.dataSourceName
                builtInMicOrientation = getBuiltInMicOrientation(orientation: dataSource.orientation)
            } else {
                name = "\(inputPort.portName): \(dataSource.dataSourceName)"
            }
            newMic = Mic(
                name: name,
                inputUid: inputPort.uid,
                dataSourceID: dataSource.dataSourceID,
                builtInOrientation: builtInMicOrientation
            )
        } else if inputPort.portType != .builtInMic {
            newMic = Mic(name: inputPort.portName, inputUid: inputPort.uid)
        } else {
            return
        }
        if newMic == micChange {
            return
        }
        if micChange != noMic {
            makeToast(title: newMic.name)
        }
        logger.info("Mic: \(newMic.name)")
        currentMic = newMic
        micChange = newMic
    }

    private func getBuiltInMicOrientation(orientation: AVAudioSession.Orientation?) -> SettingsMic? {
        guard let orientation else {
            return nil
        }
        switch orientation {
        case .bottom:
            return .bottom
        case .front:
            return .front
        case .back:
            return .back
        default:
            return nil
        }
    }

    func listMics() -> [Mic] {
        var mics: [Mic] = []
        let session = AVAudioSession.sharedInstance()
        for inputPort in session.availableInputs ?? [] {
            if let dataSources = inputPort.dataSources, !dataSources.isEmpty {
                for dataSource in dataSources {
                    var name: String
                    var builtInOrientation: SettingsMic?
                    if inputPort.portType == .builtInMic {
                        name = dataSource.dataSourceName
                        builtInOrientation = getBuiltInMicOrientation(orientation: dataSource.orientation)
                    } else {
                        name = "\(inputPort.portName): \(dataSource.dataSourceName)"
                    }
                    mics.append(Mic(
                        name: name,
                        inputUid: inputPort.uid,
                        dataSourceID: dataSource.dataSourceID,
                        builtInOrientation: builtInOrientation
                    ))
                }
            } else {
                mics.append(Mic(name: inputPort.portName, inputUid: inputPort.uid))
            }
        }
        for rtmpCamera in rtmpCameras() {
            guard let stream = getRtmpStream(camera: rtmpCamera) else {
                continue
            }
            if isRtmpStreamConnected(streamKey: stream.streamKey) {
                mics.append(Mic(
                    name: rtmpCamera,
                    inputUid: stream.id.uuidString,
                    builtInOrientation: .rtmp
                ))
            }
        }
        return mics
    }

    private func setMic() {
        var wantedOrientation: AVAudioSession.Orientation
        switch database.mic! {
        case .bottom:
            wantedOrientation = .bottom
        case .front:
            wantedOrientation = .front
        case .back:
            wantedOrientation = .back
        case .top:
            wantedOrientation = .top
        case .rtmp:
            wantedOrientation = .bottom
        }
        let session = AVAudioSession.sharedInstance()
        for inputPort in session.availableInputs ?? [] {
            if inputPort.portType != .builtInMic {
                continue
            }
            if let dataSources = inputPort.dataSources, !dataSources.isEmpty {
                for dataSource in dataSources where dataSource.orientation == wantedOrientation {
                    do {
                        try setBuiltInMicAudioMode(dataSource: dataSource)
                        try inputPort.setPreferredDataSource(dataSource)
                    } catch {
                        logger.error("Failed to set mic as preferred with error \(error)")
                    }
                }
            }
        }
    }

    func setMicFromSettings() {
        selectMicByOrientation(orientation: database.mic!)
    }

    func selectMicByOrientation(orientation: SettingsMic) {
        guard let mic = listMics().first(where: { mic in mic.builtInOrientation == orientation }) else {
            logger.info("Mic with orientation \(orientation) not found")
            makeErrorToast(
                title: String(localized: "Mic not found"),
                subTitle: String(localized: "Mic orientation \(orientation.rawValue)")
            )
            return
        }
        if var builtInOrientation = mic.builtInOrientation {
            if builtInOrientation == .rtmp {
                builtInOrientation = .bottom
            }
            if database.mic != builtInOrientation {
                database.mic = builtInOrientation
                store()
            }
        }
        selectMic(mic: mic)
    }

    func selectMicById(id: String) {
        guard let mic = listMics().first(where: { mic in mic.id == id }) else {
            logger.info("Mic with id \(id) not found")
            makeErrorToast(
                title: String(localized: "Mic not found"),
                subTitle: String(localized: "Mic id \(id)")
            )
            return
        }
        if var builtInOrientation = mic.builtInOrientation {
            if builtInOrientation == .rtmp {
                builtInOrientation = .bottom
            }
            database.mic = builtInOrientation
            store()
        }
        selectMic(mic: mic)
    }

    private func selectMic(mic: Mic) {
        if mic.builtInOrientation == .rtmp {
            currentMic = mic
            let cameraId = getRtmpStream(camera: mic.name)?.id ?? .init()
            media.attachRtmpAudio(cameraId: cameraId, device: AVCaptureDevice.default(for: .audio))
            remoteControlStreamer?.stateChanged(state: RemoteControlState(mic: mic.id))
        } else {
            let session = AVAudioSession.sharedInstance()
            do {
                for inputPort in session.availableInputs ?? [] {
                    if mic.inputUid != inputPort.uid {
                        continue
                    }
                    try session.setPreferredInput(inputPort)
                    if let dataSourceID = mic.dataSourceID {
                        for dataSource in inputPort.dataSources ?? [] {
                            if dataSourceID != dataSource.dataSourceID {
                                continue
                            }
                            try setBuiltInMicAudioMode(dataSource: dataSource)
                            try session.setInputDataSource(dataSource)
                        }
                    }
                }
                currentMic = mic
                remoteControlStreamer?.stateChanged(state: RemoteControlState(mic: mic.id))
            } catch {
                logger.error("Failed to select mic: \(error)")
                makeErrorToast(
                    title: String(localized: "Failed to select mic"),
                    subTitle: error.localizedDescription
                )
            }
        }
    }

    private func setBuiltInMicAudioMode(dataSource: AVAudioSessionDataSourceDescription) throws {
        try dataSource.setPreferredPolarPattern(.none)
    }
}

extension Model {
    private func updateLocation() {
        var newLocation = locationManager.status()
        if let realtimeIrl {
            newLocation += realtimeIrl.status()
        }
        if location != newLocation {
            location = newLocation
        }
    }

    func reloadLocation() {
        locationManager.stop()
        if isLocationEnabled() {
            locationManager.start(onUpdate: handleLocationUpdate)
        }
        reloadRealtimeIrl()
    }

    func isLocationEnabled() -> Bool {
        return database.location!.enabled
    }

    private func handleLocationUpdate(location: CLLocation) {
        guard isLive else {
            return
        }
        guard !isLocationInPrivacyRegion(location: location) else {
            return
        }
        realtimeIrl?.update(location: location)
    }

    private func isLocationInPrivacyRegion(location: CLLocation) -> Bool {
        for region in database.location!.privacyRegions
            where region.contains(coordinate: location.coordinate)
        {
            return true
        }
        return false
    }

    func getLatestKnownLocation() -> (Double, Double)? {
        return locationManager.getLatestKnownLocation()
    }

    func isRealtimeIrlConfigured() -> Bool {
        return stream.realtimeIrlEnabled! && !stream.realtimeIrlPushKey!.isEmpty
    }

    func reloadRealtimeIrl() {
        realtimeIrl?.stop()
        realtimeIrl = nil
        if isRealtimeIrlConfigured() {
            realtimeIrl = RealtimeIrl(pushKey: stream.realtimeIrlPushKey!)
        }
    }
}

extension Model {
    func toggleDrawOnStream() {
        showDrawOnStream.toggle()
    }

    func drawOnStreamLineComplete() {
        drawOnStreamEffect.updateOverlay(
            videoSize: media.getVideoSize(),
            size: drawOnStreamSize,
            lines: drawOnStreamLines
        )
        media.registerEffect(drawOnStreamEffect)
    }

    func drawOnStreamWipe() {
        drawOnStreamLines = []
        drawOnStreamEffect.updateOverlay(
            videoSize: media.getVideoSize(),
            size: drawOnStreamSize,
            lines: drawOnStreamLines
        )
        media.unregisterEffect(drawOnStreamEffect)
    }

    func drawOnStreamUndo() {
        guard !drawOnStreamLines.isEmpty else {
            return
        }
        drawOnStreamLines.removeLast()
        drawOnStreamEffect.updateOverlay(
            videoSize: media.getVideoSize(),
            size: drawOnStreamSize,
            lines: drawOnStreamLines
        )
        if drawOnStreamLines.isEmpty {
            media.unregisterEffect(drawOnStreamEffect)
        }
    }
}

extension Model {
    private func getWebBrowserUrl() -> URL? {
        if let url = URL(string: webBrowserUrl), let scehme = url.scheme, !scehme.isEmpty {
            return url
        }
        if webBrowserUrl.contains("."), let url = URL(string: "https://\(webBrowserUrl)") {
            return url
        }
        return URL(string: "https://www.google.com/search?q=\(webBrowserUrl)")
    }

    func loadWebBrowserUrl() {
        guard let url = getWebBrowserUrl() else {
            return
        }
        webBrowser?.load(URLRequest(url: url))
    }

    func loadWebBrowserHome() {
        webBrowserUrl = database.webBrowser!.home
        loadWebBrowserUrl()
    }

    func getWebBrowser() -> WKWebView {
        if webBrowser == nil {
            webBrowser = WKWebView()
            webBrowser?.navigationDelegate = self
            DispatchQueue.main.async {
                self.loadWebBrowserHome()
            }
        }
        return webBrowser!
    }
}

extension Model: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation _: WKNavigation!) {
        webBrowserUrl = webView.url?.absoluteString ?? ""
    }
}

extension Model {
    func setFocusPointOfInterest(focusPoint: CGPoint) {
        guard
            let device = cameraDevice, device.isFocusPointOfInterestSupported
        else {
            logger.warning("Tap to focus not supported for this camera")
            makeErrorToast(title: String(localized: "Tap to focus not supported for this camera"))
            return
        }
        var focusPointOfInterest = focusPoint
        if stream.portrait! {
            focusPointOfInterest.x = focusPoint.y
            focusPointOfInterest.y = 1 - focusPoint.x
        } else if getOrientation() == .landscapeRight {
            focusPointOfInterest.x = 1 - focusPoint.x
            focusPointOfInterest.y = 1 - focusPoint.y
        }
        do {
            try device.lockForConfiguration()
            device.focusPointOfInterest = focusPointOfInterest
            device.focusMode = .autoFocus
            device.exposurePointOfInterest = focusPointOfInterest
            device.exposureMode = .autoExpose
            device.unlockForConfiguration()
            manualFocusPoint = focusPoint
            startMotionDetection()
        } catch let error as NSError {
            logger.error("while locking device for focusPointOfInterest: \(error)")
        }
        manualFocusesEnabled[device] = false
        manualFocusEnabled = false
    }

    func setAutoFocus() {
        stopMotionDetection()
        guard let device = cameraDevice, device.isFocusPointOfInterestSupported else {
            return
        }
        do {
            try device.lockForConfiguration()
            device.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5)
            device.focusMode = .continuousAutoFocus
            device.exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5)
            device.exposureMode = .continuousAutoExposure
            device.unlockForConfiguration()
            manualFocusPoint = nil
        } catch let error as NSError {
            logger.error("while locking device for focusPointOfInterest: \(error)")
        }
        manualFocusesEnabled[device] = false
        manualFocusEnabled = false
    }

    func setManualFocus(lensPosition: Float) {
        guard
            let device = cameraDevice, device.isLockingFocusWithCustomLensPositionSupported
        else {
            makeErrorToast(title: String(localized: "Manual focus not supported for this camera"))
            return
        }
        stopMotionDetection()
        do {
            try device.lockForConfiguration()
            device.setFocusModeLocked(lensPosition: lensPosition)
            device.unlockForConfiguration()
        } catch let error as NSError {
            logger.error("while locking device for manual focus: \(error)")
        }
        manualFocusPoint = nil
        manualFocusesEnabled[device] = true
        manualFocusEnabled = true
        manualFocuses[device] = lensPosition
    }

    private func setFocusAfterCameraAttach() {
        guard let device = cameraDevice else {
            return
        }
        manualFocus = manualFocuses[device] ?? device.lensPosition
        manualFocusEnabled = manualFocusesEnabled[device] ?? false
        if !manualFocusEnabled {
            setAutoFocus()
        }
        if focusObservation != nil {
            stopObservingFocus()
            startObservingFocus()
        }
    }

    func isCameraSupportingManualFocus() -> Bool {
        if let device = cameraDevice, device.isLockingFocusWithCustomLensPositionSupported {
            return true
        } else {
            return false
        }
    }

    func startObservingFocus() {
        guard let device = cameraDevice else {
            return
        }
        manualFocus = device.lensPosition
        focusObservation = device.observe(\.lensPosition) { [weak self] _, _ in
            guard let self else {
                return
            }
            DispatchQueue.main.async {
                guard !self.editingManualFocus else {
                    return
                }
                self.manualFocuses[device] = device.lensPosition
                self.manualFocus = device.lensPosition
            }
        }
    }

    func stopObservingFocus() {
        focusObservation = nil
    }
}

extension Model {
    func setAutoIso() {
        guard
            let device = cameraDevice, device.isExposureModeSupported(.continuousAutoExposure)
        else {
            makeErrorToast(title: String(localized: "Continuous auto exposure not supported for this camera"))
            return
        }
        do {
            try device.lockForConfiguration()
            device.exposureMode = .continuousAutoExposure
            device.unlockForConfiguration()
        } catch let error as NSError {
            logger.error("while locking device for continuous auto exposure: \(error)")
        }
        manualIsosEnabled[device] = false
        manualIsoEnabled = false
    }

    func setManualIso(factor: Float) {
        guard
            let device = cameraDevice, device.isExposureModeSupported(.custom)
        else {
            makeErrorToast(title: String(localized: "Manual exposure not supported for this camera"))
            return
        }
        let iso = factorToIso(device: device, factor: factor)
        do {
            try device.lockForConfiguration()
            device.setExposureModeCustom(duration: AVCaptureDevice.currentExposureDuration, iso: iso) { _ in
            }
            device.unlockForConfiguration()
        } catch let error as NSError {
            logger.error("while locking device for manual exposure: \(error)")
        }
        manualIsosEnabled[device] = true
        manualIsoEnabled = true
        manualIsos[device] = iso
    }

    private func setIsoAfterCameraAttach(device: AVCaptureDevice) {
        manualIso = manualIsos[device] ?? factorFromIso(device: device, iso: device.iso)
        manualIsoEnabled = manualIsosEnabled[device] ?? false
        if manualIsoEnabled {
            setManualIso(factor: manualIso)
        }
        if isoObservation != nil {
            stopObservingIso()
            startObservingIso()
        }
    }

    func isCameraSupportingManualIso() -> Bool {
        if let device = cameraDevice, device.isExposureModeSupported(.custom) {
            return true
        } else {
            return false
        }
    }

    func startObservingIso() {
        guard let device = cameraDevice else {
            return
        }
        manualIso = factorFromIso(device: device, iso: device.iso)
        isoObservation = device.observe(\.iso) { [weak self] _, _ in
            guard let self else {
                return
            }
            DispatchQueue.main.async {
                guard !self.editingManualIso else {
                    return
                }
                let iso = factorFromIso(device: device, iso: device.iso)
                self.manualIsos[device] = iso
                self.manualIso = iso
            }
        }
    }

    func stopObservingIso() {
        isoObservation = nil
    }
}

extension Model {
    func setAutoWhiteBalance() {
        guard
            let device = cameraDevice, device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance)
        else {
            makeErrorToast(
                title: String(localized: "Continuous auto white balance not supported for this camera")
            )
            return
        }
        do {
            try device.lockForConfiguration()
            device.whiteBalanceMode = .continuousAutoWhiteBalance
            device.unlockForConfiguration()
        } catch let error as NSError {
            logger.error("while locking device for continuous auto white balance: \(error)")
        }
        manualWhiteBalancesEnabled[device] = false
        manualWhiteBalanceEnabled = false
    }

    func setManualWhiteBalance(factor: Float) {
        guard
            let device = cameraDevice, device.isLockingWhiteBalanceWithCustomDeviceGainsSupported
        else {
            makeErrorToast(title: String(localized: "Manual white balance not supported for this camera"))
            return
        }
        do {
            try device.lockForConfiguration()
            device.setWhiteBalanceModeLocked(with: factorToWhiteBalance(device: device, factor: factor))
            device.unlockForConfiguration()
        } catch let error as NSError {
            logger.error("while locking device for manual white balance: \(error)")
        }
        manualWhiteBalancesEnabled[device] = true
        manualWhiteBalanceEnabled = true
        manualWhiteBalances[device] = factor
    }

    private func setWhiteBalanceAfterCameraAttach(device: AVCaptureDevice) {
        manualWhiteBalance = manualWhiteBalances[device] ?? 0.5
        manualWhiteBalanceEnabled = manualWhiteBalancesEnabled[device] ?? false
        if manualWhiteBalanceEnabled {
            setManualWhiteBalance(factor: manualWhiteBalance)
        }
        if whiteBalanceObservation != nil {
            stopObservingWhiteBalance()
            startObservingWhiteBalance()
        }
    }

    func isCameraSupportingManualWhiteBalance() -> Bool {
        if let device = cameraDevice, device.isLockingWhiteBalanceWithCustomDeviceGainsSupported {
            return true
        } else {
            return false
        }
    }

    func startObservingWhiteBalance() {
        guard let device = cameraDevice else {
            return
        }
        manualWhiteBalance = factorFromWhiteBalance(
            device: device,
            gains: device.deviceWhiteBalanceGains.clamped(maxGain: device.maxWhiteBalanceGain)
        )
        whiteBalanceObservation = device.observe(\.deviceWhiteBalanceGains) { [weak self] _, _ in
            guard let self else {
                return
            }
            DispatchQueue.main.async {
                guard !self.editingManualWhiteBalance else {
                    return
                }
                let factor = factorFromWhiteBalance(
                    device: device,
                    gains: device.deviceWhiteBalanceGains.clamped(maxGain: device.maxWhiteBalanceGain)
                )
                self.manualWhiteBalances[device] = factor
                self.manualWhiteBalance = factor
            }
        }
    }

    func stopObservingWhiteBalance() {
        whiteBalanceObservation = nil
    }
}

extension Model: SampleBufferReceiverDelegate {
    func senderConnected() {
        DispatchQueue.main.async {
            self.handleSampleBufferSenderConnected()
        }
    }

    func senderDisconnected() {
        DispatchQueue.main.async {
            self.handleSampleBufferSenderDisconnected()
        }
    }

    func handleSampleBuffer(type: RPSampleBufferType, sampleBuffer: CMSampleBuffer) {
        handleSampleBufferSenderBuffer(type, sampleBuffer)
    }
}

// private let sampleBufferCameraId = UUID()

extension Model {
    private func handleSampleBufferSenderConnected() {
        makeToast(
            title: String(localized: "Screen recording started"),
            subTitle: "DOES NOT YET WORK!!!"
        )
        // media.addRtmpCamera(cameraId: sampleBufferCameraId, latency: 0.5)
        // attachRtmpCamera(cameraId: sampleBufferCameraId)
    }

    private func handleSampleBufferSenderDisconnected() {
        makeToast(
            title: String(localized: "Screen recording stopped"),
            subTitle: "DOES NOT YET WORK!!!"
        )
        // media.removeRtmpCamera(cameraId: sampleBufferCameraId)
    }

    private func handleSampleBufferSenderBuffer(_ type: RPSampleBufferType, _ sampleBuffer: CMSampleBuffer) {
        switch type {
        case .video:
            logger.info("Video sample buffer: \(sampleBuffer)")
        // media.addRtmpSampleBuffer(cameraId: sampleBufferCameraId, sampleBuffer: sampleBuffer)
        default:
            break
        }
    }
}

extension Model: SrtlaServerDelegate {
    func srtlaServerOnAudioBuffer(streamId _: String, buffer _: AVAudioPCMBuffer) {
        // guard let cameraId = getSrtlaStream(streamId: streamId)?.id else {
        //     return
        // }
        // media.addRtmpAudioBuffer(cameraId: cameraId, audioBuffer: buffer)
    }

    func srtlaServerOnVideoBuffer(streamId: String, sampleBuffer: CMSampleBuffer) {
        guard let cameraId = getSrtlaStream(streamId: streamId)?.id else {
            return
        }
        media.addRtmpSampleBuffer(cameraId: cameraId, sampleBuffer: sampleBuffer)
    }

    func srtlaServerOnClientStart(streamId: String) {
        DispatchQueue.main.async {
            let camera = self.getSrtlaStream(streamId: streamId)?.camera() ?? srtlaCamera(name: "Unknown")
            self.makeToast(title: "\(camera) connected")
            guard let stream = self.getSrtlaStream(streamId: streamId) else {
                return
            }
            let latency = Double(stream.latency!) / 1000
            self.media.addRtmpCamera(cameraId: stream.id, latency: latency)
            self.media.addRtmpAudio(cameraId: stream.id, latency: latency)
        }
    }

    func srtlaServerOnClientStop(streamId: String) {
        DispatchQueue.main.async {
            let camera = self.getSrtlaStream(streamId: streamId)?.camera() ?? srtlaCamera(name: "Unknown")
            self.makeToast(title: "\(camera) disconnected")
            guard let stream = self.getSrtlaStream(streamId: streamId) else {
                return
            }
            self.media.removeRtmpCamera(cameraId: stream.id)
            self.media.removeRtmpAudio(cameraId: stream.id)
            if self.currentMic.inputUid == stream.id.uuidString {
                self.setMicFromSettings()
            }
        }
    }
}
