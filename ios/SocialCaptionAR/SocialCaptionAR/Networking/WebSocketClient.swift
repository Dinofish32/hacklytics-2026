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

    private func log(_ message: String) {
        print("[WebSocketClient] \(message)")
    }

    func connect(url: URL) {
        // Single bidirectional socket:
        // - receives caption_event stream from backend
        // - sends one meeting_payload when recording stops
        log("connect() called with URL: \(url.absoluteString)")
        disconnect()
        onStatus?("Connecting...")

        task = session.webSocketTask(with: url)
        task?.resume()
        log("WebSocket task resumed")

        onStatus?("Connected")
        log("Status set to Connected")
        receiveLoop()
    }

    func disconnect() {
        if task != nil {
            log("disconnect() called; closing websocket task")
        }
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        onStatus?("Disconnected")
    }

    private func receiveLoop() {
        task?.receive { [weak self] result in
            guard let self else { return }

            switch result {
            case .failure(let err):
                self.log("Receive error: \(err.localizedDescription)")
                self.onStatus?("WS error: \(err.localizedDescription)")
                return

            case .success(let message):
                switch message {
                case .string(let s):
                    self.log("Received text message (\(s.count) chars)")
                    self.handle(text: s)
                case .data(let d):
                    self.log("Received binary message (\(d.count) bytes)")
                    if let s = String(data: d, encoding: .utf8) {
                        self.handle(text: s)
                    } else {
                        self.log("Binary payload could not be UTF-8 decoded")
                    }
                @unknown default:
                    self.log("Received unknown websocket message type")
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
                self.log(
                    "Decoded caption_event: is_final=\(ev.isFinal), text_len=\(ev.text.count), " +
                    "tone=\(ev.toneValue.label), volume=\(String(format: "%.3f", ev.volumeValue))"
                )
                onCaptionEvent?(CaptionEvent(
                    type: ev.type,
                    t_ms: ev.t_ms,
                    text: ev.text,
                    is_final: ev.is_final,
                    tone: ev.tone,
                    volume: ev.volume
                ))
            } else {
                self.log("Ignored non-caption event type: \(ev.type)")
            }
        } catch {
            self.log("Failed to decode incoming message as CaptionEvent: \(error.localizedDescription)")
        }
    }

    func sendMeetingPayload(_ payload: MeetingPayloadEvent) async throws {
        // Reuse the same websocket connection for final upload.
        guard let task else { throw WebSocketClientError.disconnected }
        let data = try JSONEncoder().encode(payload)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw WebSocketClientError.encodingFailed
        }
        log(
            "Sending meeting_payload: transcripts=\(payload.transcripts.count), " +
            "participants=\(payload.participants.count), bytes=\(data.count)"
        )
        try await task.send(.string(jsonString))
        log("meeting_payload sent successfully")
    }
}
