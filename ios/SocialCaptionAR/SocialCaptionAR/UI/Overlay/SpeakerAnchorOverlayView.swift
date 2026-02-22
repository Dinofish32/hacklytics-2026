//
//  SpeakerAnchorOverlayView.swift
//  SocialCaptionAR
//
//  Created by Akshaj Nadimpalli on 2/21/26.
//

import SwiftUI
import AVFoundation

struct SpeakerAnchorOverlayView: View {
    let faces: [TrackedFace]
    let activeFaceId: UUID?
    let latestCaption: CaptionBubbleState?
    let previewLayer: AVCaptureVideoPreviewLayer

    private let defaultTone = Tone(label: “neutral”, confidence: 0.0, hex: “#9CA3AF”)

    var body: some View {
        if let id = activeFaceId,
           let face = faces.first(where: { $0.id == id }) {

            let metaRect = CGRect(
                x: face.visionBoundingBox.minX,
                y: 1.0 - face.visionBoundingBox.maxY,
                width: face.visionBoundingBox.width,
                height: face.visionBoundingBox.height
            )
            let rect = previewLayer.layerRectConverted(fromMetadataOutputRect: metaRect)

            // Use live caption data when available, otherwise show placeholder
            let text = latestCaption?.text ?? “”
            let tone = latestCaption?.tone ?? defaultTone
            let volume = latestCaption?.volume ?? 0.0

            VStack(spacing: 10) {
                CaptionBubbleView(
                    text: text,
                    tone: tone,
                    volume: volume
                )
                .opacity(0.85)
            }
            .frame(maxWidth: 360)
            .position(
                x: rect.midX,
                y: min(rect.maxY + 90, UIScreen.main.bounds.height - 90)
            )
            .allowsHitTesting(false)
        }
    }
}
