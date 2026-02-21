//
//  MotionSpeakerDetector.swift
//  SocialCaptionAR
//
//  Created by Akshaj Nadimpalli on 2/21/26.
//

import Foundation
import CoreGraphics

/// Speaker selection driven primarily by arm motion (shoulder/elbow/wrist) nearest each face.
/// Keeps captions under SOME face always (fallback to largest face).
final class MotionSpeakerDetector {

    struct Output {
        let activeFaceId: UUID?
        let didChange: Bool
    }

    private struct PerFaceState {
        var lastArmCentroid: CGPoint?
        var armEnergyEMA: Double = 0

        var lastMouthCentroid: CGPoint?
        var mouthEnergyEMA: Double = 0

        var lastUpdate: TimeInterval = 0
        var lastScore: Double = 0
    }

    private var states: [UUID: PerFaceState] = [:]
    private var activeFaceId: UUID? = nil

    private var challengerId: UUID? = nil
    private var challengerSince: TimeInterval = 0
    private var lockUntil: TimeInterval = 0

    // --- Tunables (demo-friendly) ---
    private let ttl: TimeInterval = 1.2
    private let alpha: Double = 0.22

    // weights: ARMS dominate
    private let wArms: Double = 1.0
    private let wMouth: Double = 0.12

    // switching behavior (anti-jitter)
    private let switchHold: TimeInterval = 0.55
    private let lockDuration: TimeInterval = 0.95
    private let winRatio: Double = 1.35
    private let winMargin: Double = 0.006

    // gating: only count arm joints near a face
    private let assignMaxDist: Double = 0.22

    func update(faces: [TrackedFace],
                bodies: [VisionPoseTracker.BodyPose],
                now: TimeInterval) -> Output {

        states = states.filter { now - $0.value.lastUpdate < ttl }

        guard !faces.isEmpty else {
            return Output(activeFaceId: nil, didChange: false)
        }

        // Precompute face info
        let faceInfo: [(id: UUID, center: CGPoint, area: Double, bbox: CGRect, mouth: [CGPoint])] = faces.map { f in
            let bb = f.visionBoundingBox
            let center = CGPoint(x: bb.midX, y: bb.midY)
            let area = Double(bb.width * bb.height)
            return (f.id, center, area, bb, f.mouthPoints)
        }

        // Extract all arm joints (Vision normalized, bottom-left)
        let allArmPoints: [CGPoint] = bodies.flatMap { b in
            [
                b.leftShoulder, b.leftElbow, b.leftWrist,
                b.rightShoulder, b.rightElbow, b.rightWrist
            ].compactMap { $0 }
        }

        // Update per-face energy
        for finfo in faceInfo {
            var st = states[finfo.id] ?? PerFaceState()

            // Collect arm joints near this face
            let nearbyArmPts = allArmPoints.filter { p in
                let d = hypot(Double(p.x - finfo.center.x), Double(p.y - finfo.center.y))
                return d <= assignMaxDist
            }

            // Arm centroid motion energy
            if let armC = centroid(of: nearbyArmPts) {
                if let last = st.lastArmCentroid {
                    let dm = hypot(Double(armC.x - last.x), Double(armC.y - last.y))
                    st.armEnergyEMA = (1 - alpha) * st.armEnergyEMA + alpha * dm
                } else {
                    st.armEnergyEMA = (1 - alpha) * st.armEnergyEMA
                }
                st.lastArmCentroid = armC
            } else {
                st.lastArmCentroid = nil
                st.armEnergyEMA = (1 - alpha) * st.armEnergyEMA
            }

            // Mouth fallback energy (helps when speaker talks without moving arms)
            if let mc = centroid(of: finfo.mouth) {
                if let last = st.lastMouthCentroid {
                    let dm = hypot(Double(mc.x - last.x), Double(mc.y - last.y))
                    st.mouthEnergyEMA = (1 - alpha) * st.mouthEnergyEMA + alpha * dm
                } else {
                    st.mouthEnergyEMA = (1 - alpha) * st.mouthEnergyEMA
                }
                st.lastMouthCentroid = mc
            } else {
                st.lastMouthCentroid = nil
                st.mouthEnergyEMA = (1 - alpha) * st.mouthEnergyEMA
            }

            st.lastUpdate = now
            st.lastScore = wArms * st.armEnergyEMA + wMouth * st.mouthEnergyEMA
            states[finfo.id] = st
        }

        // Score faces
        var scored: [(id: UUID, score: Double, area: Double)] = []
        scored.reserveCapacity(faceInfo.count)

        for finfo in faceInfo {
            let score = states[finfo.id]?.lastScore ?? 0
            scored.append((finfo.id, score, finfo.area))
        }

        // Sort by score, tie-breaker by biggest face
        scored.sort {
            if abs($0.score - $1.score) > 1e-9 { return $0.score > $1.score }
            return $0.area > $1.area
        }

        let top = scored[0]

        // Always have an active face if faces exist
        if activeFaceId == nil {
            activeFaceId = biggestFaceId(faceInfo)
        }

        // Respect lock
        if now < lockUntil {
            return Output(activeFaceId: activeFaceId, didChange: false)
        }

        let currentId = activeFaceId ?? top.id
        let currentScore = scored.first(where: { $0.id == currentId })?.score ?? 0.00001

        // If top is current, stop challenging
        if top.id == currentId {
            challengerId = nil
            return Output(activeFaceId: activeFaceId, didChange: false)
        }

        let isClearWinner = (top.score >= currentScore * winRatio) && ((top.score - currentScore) >= winMargin)

        if isClearWinner {
            if challengerId != top.id {
                challengerId = top.id
                challengerSince = now
            } else if now - challengerSince >= switchHold {
                activeFaceId = top.id
                challengerId = nil
                lockUntil = now + lockDuration
                return Output(activeFaceId: activeFaceId, didChange: true)
            }
        } else {
            challengerId = nil
        }

        // If current face disappears, fall back to biggest
        if !faceInfo.contains(where: { $0.id == currentId }) {
            activeFaceId = biggestFaceId(faceInfo)
            return Output(activeFaceId: activeFaceId, didChange: true)
        }

        return Output(activeFaceId: activeFaceId, didChange: false)
    }

    private func centroid(of pts: [CGPoint]) -> CGPoint? {
        guard !pts.isEmpty else { return nil }
        var sx: Double = 0
        var sy: Double = 0
        for p in pts { sx += Double(p.x); sy += Double(p.y) }
        return CGPoint(x: sx / Double(pts.count), y: sy / Double(pts.count))
    }

    private func biggestFaceId(_ faces: [(id: UUID, center: CGPoint, area: Double, bbox: CGRect, mouth: [CGPoint])]) -> UUID? {
        faces.max(by: { $0.area < $1.area })?.id
    }
}
