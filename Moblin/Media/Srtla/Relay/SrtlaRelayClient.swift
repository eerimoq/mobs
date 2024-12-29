import Foundation
import Network
import SwiftUI

private let srtlaRelayClientQueue = DispatchQueue(label: "com.eerimoq.srtla-relay-client")

enum SrtlaRelayClientState: String {
    case none = "None"
    case connecting = "Connecting"
    case connected = "Connected"
    case waitingForCellular = "Waiting for cellular"
    case wrongPassword = "Wrong password"
    case unknownError = "Unknown error"
}

protocol SrtlaRelayClientDelegate: AnyObject {
    func srtlaRelayClientNewState(state: SrtlaRelayClientState)
}

class SrtlaRelayClient {
    private var clientUrl: URL
    private var password: String
    private weak var delegate: (any SrtlaRelayClientDelegate)?
    private var webSocket: WebSocketClient
    private let name: String
    private var startTunnelId: Int?
    private var destination: NWEndpoint?
    private var serverListener: NWListener?
    private var serverConnection: NWConnection?
    private var destinationConnection: NWConnection?
    private var state: SrtlaRelayClientState = .none
    private var started = false
    private let reconnectTimer = SimpleTimer(queue: .main)
    @AppStorage("srtlaRelayId") var id = ""

    init(name: String, clientUrl: URL, password: String, delegate: SrtlaRelayClientDelegate) {
        self.name = name
        self.clientUrl = clientUrl
        self.password = password
        self.delegate = delegate
        webSocket = .init(url: clientUrl)
        if id.isEmpty {
            id = UUID().uuidString
        }
    }

    func start() {
        logger.info("srtla-relay-client: start")
        started = true
        startInternal()
    }

    func stop() {
        logger.info("srtla-relay-client: stop")
        stopInternal()
        started = false
    }

    private func startInternal() {
        guard started else {
            return
        }
        stopInternal()
        setState(state: .connecting)
        webSocket = .init(url: clientUrl)
        webSocket.delegate = self
        webSocket.start()
    }

    private func stopInternal() {
        setState(state: .none)
        webSocket.stop()
        stopTunnel()
    }

    private func reconnect(reason: String) {
        logger.info("srtla-relay-client: Reconnecting soon with reason \(reason)")
        reconnectTimer.startSingleShot(timeout: 5.0) {
            self.startInternal()
        }
    }

    private func setState(state: SrtlaRelayClientState) {
        guard state != self.state else {
            return
        }
        logger.info("srtla-relay-client: State change \(self.state) -> \(state)")
        self.state = state
        delegate?.srtlaRelayClientNewState(state: state)
    }

    private func send(message: SrtlaRelayMessageToServer) {
        do {
            let message = try message.toJson()
            webSocket.send(string: message)
        } catch {
            logger.info("srtla-relay-client: Encode failed")
        }
    }

    private func handleMessage(message: String) throws {
        do {
            switch try SrtlaRelayMessageToClient.fromJson(data: message) {
            case let .hello(apiVersion: apiVersion, authentication: authentication):
                handleHello(apiVersion: apiVersion, authentication: authentication)
            case let .identified(result: result):
                if !handleIdentified(result: result) {
                    logger.info("srtla-relay-client: Failed to identify")
                    return
                }
            case let .request(id: id, data: data):
                handleRequest(id: id, data: data)
            }
        } catch {
            logger.info("srtla-relay-client: Decode failed")
        }
    }

    private func handleHello(apiVersion _: String, authentication: SrtlaRelayAuthentication) {
        let hash = remoteControlHashPassword(
            challenge: authentication.challenge,
            salt: authentication.salt,
            password: password
        )
        guard let id = UUID(uuidString: id) else {
            return
        }
        send(message: .identify(id: id, name: name, authentication: hash))
    }

    private func handleIdentified(result: SrtlaRelayResult) -> Bool {
        switch result {
        case .ok:
            return true
        case .wrongPassword:
            setState(state: .wrongPassword)
        default:
            setState(state: .unknownError)
        }
        return false
    }

    private func handleRequest(id: Int, data: SrtlaRelayRequest) {
        switch data {
        case let .startTunnel(address: address, port: port):
            handleStartTunnel(id: id, address: address, port: port)
        }
    }

    private func handleStartTunnel(id: Int, address: String, port: UInt16) {
        stopTunnel()
        logger.info("srtla-relay-client: Start tunnel to \(address):\(port)")
        destination = .hostPort(host: NWEndpoint.Host(address), port: NWEndpoint.Port(integerLiteral: port))
        do {
            let options = NWProtocolUDP.Options()
            let parameters = NWParameters(dtls: .none, udp: options)
            serverListener = try NWListener(using: parameters)
        } catch {
            logger.error("srtla-relay-client: Failed to create server listener with error \(error)")
            reconnect(reason: "Failed to create listener")
            return
        }
        serverListener?.stateUpdateHandler = handleListenerStateChange(to:)
        serverListener?.newConnectionHandler = handleNewListenerConnection(connection:)
        serverListener?.start(queue: srtlaRelayClientQueue)
        let params = NWParameters(dtls: .none)
        params.requiredInterfaceType = .cellular
        params.prohibitExpensivePaths = false
        guard case let .hostPort(host, port) = destination else {
            reconnect(reason: "Failed to parse host and port")
            return
        }
        destinationConnection = NWConnection(host: host, port: port, using: params)
        destinationConnection?.stateUpdateHandler = handleDestinationStateUpdate(to:)
        destinationConnection?.start(queue: srtlaRelayClientQueue)
        setState(state: .waitingForCellular)
        startTunnelId = id
    }

    func stopTunnel() {
        serverListener?.cancel()
        serverListener = nil
        serverConnection?.cancel()
        serverConnection = nil
        destinationConnection?.cancel()
        destinationConnection = nil
        startTunnelId = nil
    }

    private func handleListenerStateChange(to state: NWListener.State) {
        switch state {
        case .setup:
            break
        case .ready:
            guard let serverListener, let startTunnelId else {
                return
            }
            let port = serverListener.port!.rawValue
            send(message: .response(id: startTunnelId, result: .ok, data: .startTunnel(port: port)))
        case .failed:
            reconnect(reason: "Listener failed")
        default:
            break
        }
    }

    private func handleDestinationStateUpdate(to state: NWConnection.State) {
        logger.debug("srtla-relay-client: Destination state change to \(state)")
        switch state {
        case .ready:
            setState(state: .connected)
            receiveDestinationPacket()
        case .failed:
            reconnect(reason: "Destination connection failed")
        default:
            setState(state: .waitingForCellular)
        }
    }

    private func handleNewListenerConnection(connection: NWConnection) {
        serverConnection = connection
        serverConnection?.start(queue: srtlaRelayClientQueue)
        receiveServerPacket()
    }

    private func receiveServerPacket() {
        serverConnection?.receiveMessage { data, _, _, error in
            if let data, !data.isEmpty {
                self.handlePacketFromServer(packet: data)
            }
            if let error {
                logger.info("srtla-relay-client: Server receive error \(error)")
                self.reconnect(reason: "Server receive error")
                return
            }
            self.receiveServerPacket()
        }
    }

    private func handlePacketFromServer(packet: Data) {
        destinationConnection?.send(content: packet, completion: .contentProcessed { _ in
        })
    }

    private func receiveDestinationPacket() {
        destinationConnection?.receiveMessage { data, _, _, error in
            if let data, !data.isEmpty {
                self.handlePacketFromDestination(packet: data)
            }
            if let error {
                logger.info("srtla-relay-client: Destination receive error \(error)")
                self.reconnect(reason: "Destination receive error")
                return
            }
            self.receiveDestinationPacket()
        }
    }

    private func handlePacketFromDestination(packet: Data) {
        serverConnection?.send(content: packet, completion: .contentProcessed { _ in
        })
    }
}

extension SrtlaRelayClient: WebSocketClientDelegate {
    func webSocketClientConnected(_: WebSocketClient) {}

    func webSocketClientDisconnected(_: WebSocketClient) {
        setState(state: .connecting)
        stopTunnel()
    }

    func webSocketClientReceiveMessage(_: WebSocketClient, string: String) {
        try? handleMessage(message: string)
    }
}
