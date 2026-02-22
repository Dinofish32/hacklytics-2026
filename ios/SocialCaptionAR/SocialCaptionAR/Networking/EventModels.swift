//
//  EventModels.swift
//  SocialCaptionAR
//
//  Created by Akshaj Nadimpalli on 2/21/26.
//

import Foundation
import SwiftUI

struct CaptionEvent: Codable {
    let type: String
    let t_ms: Int?
    let text: String
    let is_final: Bool?
    let tone: ToneDTO?
    let volume: Double?

    var isFinal: Bool { is_final ?? false }
    var toneValue: Tone {
        // iOS owns visual tone colors; backend label is the source of truth.
        guard let t = tone else {
            return Tone(label: "neutral", confidence: 0.5, hex: Tone.hexForLabel("neutral"))
        }
        let normalizedLabel = t.label.lowercased()
        return Tone(
            label: normalizedLabel,
            confidence: t.confidence,
            hex: Tone.hexForLabel(normalizedLabel)
        )
    }
    var volumeValue: Double { volume ?? 0.0 }
}

struct ToneDTO: Codable {
    let label: String
    let confidence: Double
    let color_hex: String?
}

struct Tone: Equatable {
    let label: String
    let confidence: Double
    let hex: String

    static func hexForLabel(_ label: String) -> String {
        // Single place to maintain label -> color mapping in the app UI.
        switch label.lowercased() {
        case "happy":
            return "#22C55E"
        case "excited":
            return "#F59E0B"
        case "calm":
            return "#38BDF8"
        case "sad":
            return "#3B82F6"
        case "angry":
            return "#EF4444"
        case "frustrated":
            return "#F97316"
        case "surprised":
            return "#A855F7"
        default:
            return "#9CA3AF"
        }
    }

    var color: Color { Color(hex: hex) }
}

struct MeetingTranscriptRecord: Codable {
    // Final, committed transcript row stored in-memory until meeting stops.
    let speaker_id: String?
    let text: String
    let tone: String
    let volume: Double
    let timestamp_ms: Int64
}

struct MeetingParticipantRecord: Codable {
    // One representative face image per participant ID for downstream processing.
    let speaker_id: String
    let image_base64_jpeg: String?
}

struct MeetingPayloadEvent: Encodable {
    // Final upload event sent from iOS -> backend websocket on stop recording.
    let type: String = "meeting_payload"
    let started_at_ms: Int64
    let ended_at_ms: Int64
    let transcripts: [MeetingTranscriptRecord]
    let participants: [MeetingParticipantRecord]
}
