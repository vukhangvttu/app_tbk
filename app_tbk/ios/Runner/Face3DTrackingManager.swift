import Foundation
import ARKit
import AVFoundation
import Flutter
import UIKit
import zlib

/// Helper class for GZIP compression using native system zlib
class GZipHelper {
    static func compress(_ data: Data) -> Data? {
        if data.isEmpty { return data }

        var stream = z_stream()
        let dataCount = uInt(data.count)

        return data.withUnsafeBytes { rawBufferPointer in
            guard let baseAddress = rawBufferPointer.baseAddress else { return nil }
            stream.next_in = UnsafeMutablePointer(mutating: baseAddress.assumingMemoryBound(to: Bytef.self))
            stream.avail_in = dataCount

            // 16 + MAX_WBITS (15 + 16 = 31) configures zlib for gzip format with header & trailer
            if deflateInit2_(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, 31, 8, Z_DEFAULT_STRATEGY, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) != Z_OK {
                return nil
            }

            let chunk = 16384
            var compressedData = Data()

            repeat {
                if Int(stream.total_out) >= compressedData.count {
                    compressedData.count += chunk
                }
                let totalOut = Int(stream.total_out)
                // Doc count ra bien local TRUOC khi vao withUnsafeMutableBytes:
                // doc compressedData.count ngay trong closure dang giu mutable
                // access cua chinh no la loi exclusive-access (Swift 6/Xcode 16)
                let availOut = compressedData.count - totalOut
                compressedData.withUnsafeMutableBytes { mutableRawBuffer in
                    guard let destPointer = mutableRawBuffer.baseAddress?.assumingMemoryBound(to: Bytef.self).advanced(by: totalOut) else { return }
                    stream.next_out = destPointer
                    stream.avail_out = uInt(availOut)
                }
                deflate(&stream, Z_FINISH)
            } while stream.avail_out == 0

            deflateEnd(&stream)
            compressedData.count = Int(stream.total_out)
            return compressedData
        }
    }
}

/// Structure representing a 10fps sequence frame
struct FaceSequenceSample {
    let timestamp: Double
    let blendshapes: [String: Float]
    let yaw: Float
    let pitch: Float
    let roll: Float

    func toDictionary() -> [String: Any] {
        return [
            "timestamp": timestamp,
            "blendshapes": blendshapes,
            "yaw": yaw,
            "pitch": pitch,
            "roll": roll
        ]
    }
}

/// Keyframe metadata structure
struct FaceKeyframeMeta {
    let t: Double
    let yaw: Float
    let pitch: Float

    func toDictionary() -> [String: Any] {
        return [
            "t": t,
            "yaw": yaw,
            "pitch": pitch
        ]
    }
}

/// Structure to hold recorded keyframe data
struct KeyframeRecord {
    let sectorIndex: Int
    let timestamp: Double
    let yaw: Float
    let pitch: Float
    let roll: Float
    let jpegData: Data
    let vertices: [[Float]]
    let distanceToCenter: Float
}

@objc class Face3DTrackingManager: NSObject, ARSessionDelegate, FlutterStreamHandler {
    private var methodChannel: FlutterMethodChannel?
    private var eventChannel: FlutterEventChannel?
    private var eventSink: FlutterEventSink?

    private var arSession: ARSession?
    private var isTrackingRunning = false

    // Session Parameters
    private var mode: String = "verify" // "enroll" or "verify"
    private var challengeId: String = ""

    // State Tracking
    private var sequenceSamples: [FaceSequenceSample] = []
    private var keyframeRecords: [Int: KeyframeRecord] = [:] // Sector index -> Record
    private var keyframeVerticesHistory: [[[Float]]] = [] // For 3 representative keyframes mesh

    private var lastSampleTime: TimeInterval = 0
    private var sessionStartTime: TimeInterval = 0

    // 9 Target Sectors for Enroll circle scanning (v1.2)
    // Sector 0: straight (0,0), Sector 1: up (0,+25), Sector 2: up-right (+18,+18),
    // Sector 3: right (+25,0), Sector 4: down-right (+18,-18), Sector 5: down (0,-25),
    // Sector 6: down-left (-18,-18), Sector 7: left (-25,0), Sector 8: up-left (-18,+18)
    private let targetSectors: [(yaw: Float, pitch: Float)] = [
        (0.0, 0.0),      // 0: Center / Straight
        (0.0, 25.0),     // 1: Up
        (18.0, 18.0),    // 2: Up-Right
        (25.0, 0.0),     // 3: Right
        (18.0, -18.0),   // 4: Down-Right
        (0.0, -25.0),    // 5: Down
        (-18.0, -18.0),  // 6: Down-Left
        (-25.0, 0.0),    // 7: Left
        (-18.0, 18.0)    // 8: Up-Left
    ]

    private var completedSectors: Set<Int> = []

    func register(with messenger: FlutterBinaryMessenger) {
        methodChannel = FlutterMethodChannel(name: "com.example.app_tbk/face_3d", binaryMessenger: messenger)
        eventChannel = FlutterEventChannel(name: "com.example.app_tbk/face_3d_events", binaryMessenger: messenger)

        methodChannel?.setMethodCallHandler { [weak self] (call, result) in
            self?.handleMethodCall(call, result: result)
        }

        eventChannel?.setStreamHandler(self)
    }

    private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "isSupported":
            result(ARFaceTrackingConfiguration.isSupported)

        case "startSession":
            guard ARFaceTrackingConfiguration.isSupported else {
                result(FlutterError(code: "UNSUPPORTED_HARDWARE", message: "ARFaceTracking is not supported on this device", details: nil))
                return
            }

            guard let args = call.arguments as? [String: Any] else {
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "Missing arguments", details: nil))
                return
            }

            self.mode = (args["mode"] as? String) ?? "verify"
            self.challengeId = (args["challenge_id"] as? String) ?? ""

            startTrackingSession()
            result(true)

        case "stopSession":
            stopTrackingSession()
            result(true)

        case "getCollectedPayload":
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else {
                    result(FlutterError(code: "NULL_SELF", message: "Manager released", details: nil))
                    return
                }
                let payload = self.buildPayload()
                DispatchQueue.main.async {
                    result(payload)
                }
            }

        case "getSessionProgress":
            result(getProgressState())

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - ARSession Management

    private func startTrackingSession() {
        stopTrackingSession()

        sequenceSamples.removeAll()
        keyframeRecords.removeAll()
        keyframeVerticesHistory.removeAll()
        completedSectors.removeAll()

        sessionStartTime = Date().timeIntervalSince1970
        lastSampleTime = 0

        arSession = ARSession()
        arSession?.delegate = self

        let config = ARFaceTrackingConfiguration()
        config.isLightEstimationEnabled = true

        arSession?.run(config, options: [.resetTracking, .removeExistingAnchors])
        isTrackingRunning = true
    }

    private func stopTrackingSession() {
        isTrackingRunning = false
        arSession?.pause()
        arSession?.delegate = nil
        arSession = nil
    }

    // MARK: - FlutterStreamHandler

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }

    // MARK: - ARSessionDelegate

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        guard isTrackingRunning else { return }

        guard let faceAnchor = anchors.compactMap({ $0 as? ARFaceAnchor }).first else {
            notifyEventSink(isTracked: false, status: "searching_face")
            return
        }

        guard faceAnchor.isTracked else {
            notifyEventSink(isTracked: false, status: "face_lost")
            return
        }

        let currentFrameTime = Date().timeIntervalSince1970

        // 1. Extract Euler angles from transform
        let (yaw, pitch, roll) = extractEulerAngles(from: faceAnchor.transform)

        // 2. Extract Blendshapes (52 keys)
        let blendshapes = extractBlendShapes(from: faceAnchor.blendShapes)

        // 3. Extract Vertices (~1220 float3 points)
        let vertices = extractVertices(from: faceAnchor.geometry.vertices)

        // 4. Sample sequence at ~10 fps (0.1s interval)
        if currentFrameTime - lastSampleTime >= 0.095 {
            lastSampleTime = currentFrameTime
            let sample = FaceSequenceSample(
                timestamp: currentFrameTime,
                blendshapes: blendshapes,
                yaw: yaw,
                pitch: pitch,
                roll: roll
            )
            sequenceSamples.append(sample)
        }

        // 5. Check sector mapping and store keyframes
        if let arFrame = session.currentFrame {
            processKeyframes(
                frame: arFrame,
                faceAnchor: faceAnchor,
                timestamp: currentFrameTime,
                yaw: yaw,
                pitch: pitch,
                roll: roll,
                vertices: vertices
            )
        }

        // 6. Notify progress to Flutter UI
        let progress = Double(completedSectors.count) / Double(targetSectors.count)
        notifyEventSink(
            isTracked: true,
            status: "tracking_normal",
            yaw: yaw,
            pitch: pitch,
            roll: roll,
            completedSectors: Array(completedSectors),
            progress: progress
        )
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        notifyEventSink(isTracked: false, status: "session_error: \(error.localizedDescription)")
    }

    // MARK: - Angle & Frame Processing

    /// Extract Euler angles (in DEGREES) from 4x4 transform matrix.
    /// Ensures turning head left yields NEGATIVE yaw (per spec).
    private func extractEulerAngles(from transform: simd_float4x4) -> (yaw: Float, pitch: Float, roll: Float) {
        // ARKit camera coordinate space: +X right, +Y up, +Z out towards camera
        let m13 = transform.columns.2.x
        let m23 = transform.columns.2.y
        let m33 = transform.columns.2.z

        let m11 = transform.columns.0.x
        let m12 = transform.columns.1.x

        // Pitch (rotation around X): looking up > 0, looking down < 0
        let pitchRad = asin(max(-1.0, min(1.0, -m23)))

        // Yaw (rotation around Y): user turning left -> negative yaw
        // Notice ARKit transform: turning left rotates Z axis towards -X, so m13 is negative.
        let yawRad = atan2(-m13, m33)

        // Roll (rotation around Z)
        let rollRad = atan2(m12, m11)

        let radToDeg: Float = 180.0 / .pi
        return (yaw: yawRad * radToDeg, pitch: pitchRad * radToDeg, roll: rollRad * radToDeg)
    }

    private func extractBlendShapes(from blendShapes: [ARFaceAnchor.BlendShapeLocation: NSNumber]) -> [String: Float] {
        var result: [String: Float] = [:]
        for (key, value) in blendShapes {
            result[key.rawValue] = value.floatValue
        }
        return result
    }

    // SDK moi (Xcode 16) tra geometry.vertices dang [SIMD3<Float>], SDK cu dang
    // UnsafeBufferPointer — viet generic theo Sequence de compile ca hai.
    private func extractVertices<S: Sequence>(from vertices: S) -> [[Float]] where S.Element == SIMD3<Float> {
        return vertices.map { [$0.x, $0.y, $0.z] }
    }

    private func processKeyframes(
        frame: ARFrame,
        faceAnchor: ARFaceAnchor,
        timestamp: Double,
        yaw: Float,
        pitch: Float,
        roll: Float,
        vertices: [[Float]]
    ) {
        if mode == "verify" {
            // VERIFY Mode: Requires 3 keyframes (rgb_0 straight, rgb_1 middle, rgb_2 end)
            if keyframeRecords[0] == nil {
                // rgb_0 must be straight face (yaw, pitch near 0) before action
                if abs(yaw) < 12.0 && abs(pitch) < 12.0 {
                    if let jpegData = extractFrameJPEG(frame: frame, faceAnchor: faceAnchor) {
                        keyframeRecords[0] = KeyframeRecord(
                            sectorIndex: 0,
                            timestamp: timestamp,
                            yaw: yaw,
                            pitch: pitch,
                            roll: roll,
                            jpegData: jpegData,
                            vertices: vertices,
                            distanceToCenter: 0
                        )
                    }
                }
            } else if keyframeRecords[1] == nil {
                // rgb_1: Middle of session (~1s after start)
                if timestamp - sessionStartTime >= 1.0 {
                    if let jpegData = extractFrameJPEG(frame: frame, faceAnchor: faceAnchor) {
                        keyframeRecords[1] = KeyframeRecord(
                            sectorIndex: 1,
                            timestamp: timestamp,
                            yaw: yaw,
                            pitch: pitch,
                            roll: roll,
                            jpegData: jpegData,
                            vertices: vertices,
                            distanceToCenter: 0
                        )
                    }
                }
            } else if keyframeRecords[2] == nil {
                // rgb_2: End of session (~2s after start)
                if timestamp - sessionStartTime >= 1.8 {
                    if let jpegData = extractFrameJPEG(frame: frame, faceAnchor: faceAnchor) {
                        keyframeRecords[2] = KeyframeRecord(
                            sectorIndex: 2,
                            timestamp: timestamp,
                            yaw: yaw,
                            pitch: pitch,
                            roll: roll,
                            jpegData: jpegData,
                            vertices: vertices,
                            distanceToCenter: 0
                        )
                    }
                }
            }
        } else {
            // ENROLL Mode (v1.2 Circle scan): Check 9 target sectors
            for (index, target) in targetSectors.enumerated() {
                let dist = sqrt(pow(yaw - target.yaw, 2) + pow(pitch - target.pitch, 2))
                if dist <= 12.0 {
                    // Reached target sector!
                    completedSectors.insert(index)

                    // Store or update keyframe if closer to target angle than existing record
                    if let existing = keyframeRecords[index] {
                        if dist < existing.distanceToCenter {
                            if let jpegData = extractFrameJPEG(frame: frame, faceAnchor: faceAnchor) {
                                keyframeRecords[index] = KeyframeRecord(
                                    sectorIndex: index,
                                    timestamp: timestamp,
                                    yaw: yaw,
                                    pitch: pitch,
                                    roll: roll,
                                    jpegData: jpegData,
                                    vertices: vertices,
                                    distanceToCenter: dist
                                )
                            }
                        }
                    } else {
                        if let jpegData = extractFrameJPEG(frame: frame, faceAnchor: faceAnchor) {
                            keyframeRecords[index] = KeyframeRecord(
                                sectorIndex: index,
                                timestamp: timestamp,
                                yaw: yaw,
                                pitch: pitch,
                                roll: roll,
                                jpegData: jpegData,
                                vertices: vertices,
                                distanceToCenter: dist
                            )
                        }
                    }
                }
            }
        }
    }

    /// Extract RGB image from ARFrame pixelBuffer with face cropping and compression
    private func extractFrameJPEG(frame: ARFrame, faceAnchor: ARFaceAnchor) -> Data? {
        let pixelBuffer = frame.capturedImage
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()

        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }

        // Orient correctly for front camera portrait mode
        let image = UIImage(cgImage: cgImage, scale: 1.0, orientation: .right)

        // Calculate face bounding box in normalized coordinates from geometry bounds
        let faceBox = getBoundingBox(for: faceAnchor, in: frame)

        // Crop face with ~30% margin and resize max dimension to ~640px
        return cropAndResizeJPEG(image: image, boundingBox: faceBox, targetMaxDim: 640.0)
    }

    private func getBoundingBox(for faceAnchor: ARFaceAnchor, in frame: ARFrame) -> CGRect {
        // Project 3D bounding points of face geometry onto 2D image coordinates
        let vertices = faceAnchor.geometry.vertices
        var minX = Float.greatestFiniteMagnitude
        var maxX = -Float.greatestFiniteMagnitude
        var minY = Float.greatestFiniteMagnitude
        var maxY = -Float.greatestFiniteMagnitude

        let imageSize = CGSize(width: CVPixelBufferGetWidth(frame.capturedImage), height: CVPixelBufferGetHeight(frame.capturedImage))

        for vertex in vertices {
            let vertex4 = simd_float4(vertex.x, vertex.y, vertex.z, 1.0)
            let worldPoint = faceAnchor.transform * vertex4

            // Project to 2D screen space
            let proj = frame.camera.projectPoint(simd_float3(worldPoint.x, worldPoint.y, worldPoint.z), orientation: .portrait, viewportSize: imageSize)
            minX = min(minX, Float(proj.x))
            maxX = max(maxX, Float(proj.x))
            minY = min(minY, Float(proj.y))
            maxY = max(maxY, Float(proj.y))
        }

        let width = CGFloat(maxX - minX)
        let height = CGFloat(maxY - minY)
        return CGRect(x: CGFloat(minX), y: CGFloat(minY), width: max(1, width), height: max(1, height))
    }

    private func cropAndResizeJPEG(image: UIImage, boundingBox: CGRect, targetMaxDim: CGFloat) -> Data? {
        let marginX = boundingBox.width * 0.35
        let marginY = boundingBox.height * 0.35

        let cropRect = CGRect(
            x: max(0, boundingBox.origin.x - marginX),
            y: max(0, boundingBox.origin.y - marginY),
            width: min(image.size.width - boundingBox.origin.x, boundingBox.width + marginX * 2),
            height: min(image.size.height - boundingBox.origin.y, boundingBox.height + marginY * 2)
        )

        guard cropRect.width > 10 && cropRect.height > 10,
              let cgImage = image.cgImage?.cropping(to: cropRect) else {
            return image.jpegData(compressionQuality: 0.75)
        }

        let croppedImage = UIImage(cgImage: cgImage, scale: 1.0, orientation: image.imageOrientation)
        let maxDim = max(croppedImage.size.width, croppedImage.size.height)

        if maxDim > targetMaxDim {
            let scale = targetMaxDim / maxDim
            let targetSize = CGSize(width: croppedImage.size.width * scale, height: croppedImage.size.height * scale)

            UIGraphicsBeginImageContextWithOptions(targetSize, false, 1.0)
            croppedImage.draw(in: CGRect(origin: .zero, size: targetSize))
            let resized = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            return resized?.jpegData(compressionQuality: 0.75)
        }

        return croppedImage.jpegData(compressionQuality: 0.75)
    }

    // MARK: - Payload Generation

    private func buildPayload() -> [String: Any] {
        var result: [String: Any] = [:]

        // 1. Device Info
        var sysInfo = utsname()
        uname(&sysInfo)
        let machineMirror = Mirror(reflecting: sysInfo.machine)
        let deviceModel = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        let iosVersion = UIDevice.current.systemVersion

        // 2. Prepare Keyframes & Metadata
        var framesMeta: [[String: Any]] = []
        var rgbImagesMap: [String: FlutterStandardTypedData] = [:]
        var keyframeVerticesList: [[[Float]]] = []

        let sortedKeys = keyframeRecords.keys.sorted()
        for (idx, sectorKey) in sortedKeys.enumerated() {
            if let record = keyframeRecords[sectorKey] {
                let metaItem = FaceKeyframeMeta(t: record.timestamp, yaw: record.yaw, pitch: record.pitch).toDictionary()
                framesMeta.append(metaItem)

                let fieldName = "rgb_\(idx)"
                rgbImagesMap[fieldName] = FlutterStandardTypedData(bytes: record.jpegData)

                // Select vertices for 3 keyframes mesh payload (rgb_0, middle, end)
                if keyframeVerticesList.count < 3 {
                    keyframeVerticesList.append(record.vertices)
                }
            }
        }

        // Ensure keyframeVerticesList has 3 meshes if available
        if keyframeVerticesList.isEmpty && !sequenceSamples.isEmpty {
            // Fallback mesh if no keyframes reached
            keyframeVerticesList.append(Array(repeating: [0.0, 0.0, 0.0], count: 1220))
        }
        while keyframeVerticesList.count > 0 && keyframeVerticesList.count < 3 {
            keyframeVerticesList.append(keyframeVerticesList.last!)
        }

        // 3. Meta JSON
        let metaDict: [String: Any] = [
            "challenge_id": challengeId,
            "device_model": deviceModel,
            "ios_version": iosVersion,
            "frames": framesMeta
        ]

        var metaJsonString = ""
        if let metaData = try? JSONSerialization.data(withJSONObject: metaDict, options: []),
           let str = String(data: metaData, encoding: .utf8) {
            metaJsonString = str
        }

        // 4. Mesh JSON -> GZIP
        var meshGzData = Data()
        if let meshData = try? JSONSerialization.data(withJSONObject: keyframeVerticesList, options: []),
           let compressed = GZipHelper.compress(meshData) {
            meshGzData = compressed
        }

        // 5. Sequence JSON -> GZIP
        var sequenceGzData = Data()
        let sequenceArray = sequenceSamples.map { $0.toDictionary() }
        if let seqData = try? JSONSerialization.data(withJSONObject: sequenceArray, options: []),
           let compressed = GZipHelper.compress(seqData) {
            sequenceGzData = compressed
        }

        result["meta_json"] = metaJsonString
        result["rgb_images"] = rgbImagesMap
        result["mesh_gz"] = FlutterStandardTypedData(bytes: meshGzData)
        result["sequence_gz"] = FlutterStandardTypedData(bytes: sequenceGzData)
        result["keyframe_count"] = keyframeRecords.count
        result["sample_count"] = sequenceSamples.count

        return result
    }

    private func getProgressState() -> [String: Any] {
        return [
            "is_tracked": isTrackingRunning,
            "completed_sectors": Array(completedSectors),
            "circle_progress": Double(completedSectors.count) / Double(targetSectors.count),
            "sample_count": sequenceSamples.count
        ]
    }

    private func notifyEventSink(
        isTracked: Bool,
        status: String,
        yaw: Float = 0,
        pitch: Float = 0,
        roll: Float = 0,
        completedSectors: [Int] = [],
        progress: Double = 0.0
    ) {
        guard let sink = eventSink else { return }

        let data: [String: Any] = [
            "is_tracked": isTracked,
            "status": status,
            "yaw": yaw,
            "pitch": pitch,
            "roll": roll,
            "completed_sectors": completedSectors,
            "progress": progress
        ]

        DispatchQueue.main.async {
            sink(data)
        }
    }
}
