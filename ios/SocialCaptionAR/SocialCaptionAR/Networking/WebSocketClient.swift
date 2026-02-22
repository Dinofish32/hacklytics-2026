//
//  WebSocketClient.swift
//  SocialCaptionAR
//
//  Created by Akshaj Nadimpalli on 2/21/26.
//


import Foundation

final class WebSocketClient {
    enum WebSocketClientError: Error {
        case disconnected
        case encodingFailed
    }

    private var task: URLSessionWebSocketTask?
    private let session = URLSession(configuration: .default)

    var onCaptionEvent: ((CaptionEvent) -> Void)?
    var onStatus: ((String) -> Void)?

    func connect(url: URL) {
        // Single bidirectional socket:
        // - receives caption_event stream from backend
        // - sends one meeting_payload when recording stops
        disconnect()
        onStatus?("Connecting...")

        task = session.webSocketTask(with: url)
        task?.resume()

        onStatus?("Connected")
        receiveLoop()
    }

    func disconnect() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        onStatus?("Disconnected")
    }

    private func receiveLoop() {
        task?.receive { [weak self] result in
            guard let self else { return }

            switch result {
            case .failure(let err):
                self.onStatus?("WS error: \(err.localizedDescription)")
                return

            case .success(let message):
                switch message {
                case .string(let s):
                    self.handle(text: s)
                case .data(let d):
                    if let s = String(data: d, encoding: .utf8) {
                        self.handle(text: s)
                    }
                @unknown default:
                    break
                }
            }

            self.receiveLoop()
        }
    }

    private func handle(text: String) {
        guard let data = text.data(using: .utf8) else { return }
        do {
            let ev = try JSONDecoder().decode(CaptionEvent.self, from: data)
            if ev.type == "caption_event" {
                // Forward only caption stream events to rendering pipeline.
                onCaptionEvent?(CaptionEvent(
                    type: ev.type,
                    t_ms: ev.t_ms,
                    text: ev.text,
                    is_final: ev.is_final,
                    tone: ev.tone,
                    volume: ev.volume
                ))
            }
        } catch {
            // ignore non-caption messages for now
        }
    }

    func sendMeetingPayload(_ payload: MeetingPayloadEvent) async throws {
        // Reuse the same websocket connection for final upload.
        guard let task else { throw WebSocketClientError.disconnected }
        let data = try JSONEncoder().encode(payload)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw WebSocketClientError.encodingFailed
        }
        try await task.send(.string(jsonString))
    }
}
