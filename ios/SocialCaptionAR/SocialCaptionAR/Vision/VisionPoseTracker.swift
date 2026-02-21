//
//  VisionPoseTracker.swift
//  SocialCaptionAR
//
//  Created by Akshaj Nadimpalli on 2/21/26.
//


import Foundation
import Vision
import QuartzCore
import CoreGraphics
import ImageIO

/// Tracks body pose (arms) + hand pose (optional).
/// All points returned are normalized in Vision coords (0..1) with origin bottom-left.
final class VisionPoseTracker {
    private let queue = DispatchQueue(label: "vision.pose.queue")
    private let handler = VNSequenceRequestHandler()

    private var lastRun: CFTimeInterval = 0
    private let minInterval: CFTimeInterval = 1.0 / 15.0

    // MUST match your VisionFaceTracker orientation
    private let orientation: CGImagePropertyOrientation = .up

    struct BodyPose: Identifiable {
        let id: Int

        let leftShoulder: CGPoint?
        let leftElbow: CGPoint?
        let leftWrist: CGPoint?

        let rightShoulder: CGPoint?
        let rightElbow: CGPoint?
        let rightWrist: CGPoint?
    }

    struct Output {
        let bodies: [BodyPose]
        let handPoints: [CGPoint] // normalized, bottom-left
    }

    func processFrame(pixelBuffer: CVPixelBuffer,
                      completion: @escaping (Output) -> Void) {
        let now = CACurrentMediaTime()
        if now - lastRun < minInterval { return }
        lastRun = now

        queue.async {
            let bodyReq = VNDetectHumanBodyPoseRequest()
            let handReq = VNDetectHumanHandPoseRequest()
            handReq.maximumHandCount = 4

            do {
                try self.handler.perform([bodyReq, handReq], on: pixelBuffer, orientation: self.orientation)
            } catch {
                completion(Output(bodies: [], handPoints: []))
                return
            }

            var bodiesOut: [BodyPose] = []
            if let bodies = bodyReq.results as? [VNHumanBodyPoseObservation] {
                for (idx, b) in bodies.prefix(6).enumerated() {
                    let ls = Self.point(b, .leftShoulder)
                    let le = Self.point(b, .leftElbow)
                    let lw = Self.point(b, .leftWrist)

                    let rs = Self.point(b, .rightShoulder)
                    let re = Self.point(b, .rightElbow)
                    let rw = Self.point(b, .rightWrist)

                    bodiesOut.append(
                        BodyPose(
                            id: idx,
                            leftShoulder: ls, leftElbow: le, leftWrist: lw,
                            rightShoulder: rs, rightElbow: re, rightWrist: rw
                        )
                    )
                }
            }

            var handPts: [CGPoint] = []
            if let hands = handReq.results as? [VNHumanHandPoseObservation] {
                for h in hands.prefix(4) {
                    let joints: [VNHumanHandPoseObservation.JointName] = [
                        .wrist,
                        .thumbMP, .indexMCP, .middleMCP, .ringMCP, .littleMCP
                    ]
                    for j in joints {
                        if let p = try? h.recognizedPoint(j), p.confidence >= 0.3 {
                            handPts.append(CGPoint(x: p.location.x, y: p.location.y))
                        }
                    }
                }
            }

            completion(Output(bodies: bodiesOut, handPoints: handPts))
        }
    }

    private static func point(_ obs: VNHumanBodyPoseObservation,
                              _ joint: VNHumanBodyPoseObservation.JointName,
                              minConfidence: Float = 0.3) -> CGPoint? {
        guard let p = try? obs.recognizedPoint(joint), p.confidence >= minConfidence else { return nil }
        return CGPoint(x: p.location.x, y: p.location.y)
    }
}
