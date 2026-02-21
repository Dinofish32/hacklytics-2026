//
//  EventModels.swift
//  SocialCaptionAR
//
//  Created by Akshaj Nadimpalli on 2/21/26.
//

import Foundation
import SwiftUI

struct CaptionEvent: Codable {
    let t_ms: Int
    let text: String
    let tone: String
    let volume: Double
}

struct Tone: Equatable {
    let label: String

    var color: Color {
        switch label.lowercased() {
        case "happy":       return Color(hex: "#22C55E")
        case "excited":     return Color(hex: "#F59E0B")
        case "calm":        return Color(hex: "#3B82F6")
        case "sad":         return Color(hex: "#6366F1")
        case "angry":       return Color(hex: "#EF4444")
        case "frustrated":  return Color(hex: "#F97316")
        case "surprised":   return Color(hex: "#A855F7")
        default:            return Color(hex: "#9CA3AF")
        }
    }
}
