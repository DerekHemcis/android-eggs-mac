import AppKit
import ScreenSaver
import AVFoundation
import CoreVideo

// Config
let W = 2560, H = 1440
let FPS: Int32 = 30
let DURATION_SECONDS = 180
let FADE_SECONDS: Float = 1.5
let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "dist/Landroid 锁屏.mov"

_ = NSApplication.shared

guard let view = LandroidView(frame: NSRect(x: 0, y: 0, width: W, height: H), isPreview: false) else {
    print("cannot create view"); exit(1)
}

let url = URL(fileURLWithPath: outPath)
try? FileManager.default.removeItem(at: url)
let writer = try! AVAssetWriter(outputURL: url, fileType: .mov)
let settings: [String: Any] = [
    AVVideoCodecKey: AVVideoCodecType.hevc,
    AVVideoWidthKey: W,
    AVVideoHeightKey: H,
    AVVideoCompressionPropertiesKey: [
        AVVideoAverageBitRateKey: 10_000_000,
        AVVideoMaxKeyFrameIntervalKey: 60
    ]
]
let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
input.expectsMediaDataInRealTime = false
let attrs: [String: Any] = [
    kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
    kCVPixelBufferWidthKey as String: W,
    kCVPixelBufferHeightKey as String: H
]
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: attrs)
writer.add(input)
writer.startWriting()
writer.startSession(atSourceTime: .zero)

let colorSpace = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4,
                    space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue)!
ctx.interpolationQuality = .high

let totalFrames = DURATION_SECONDS * Int(FPS)
let dt: Float = 1.0 / Float(FPS)
var written = 0
let start = CFAbsoluteTimeGetCurrent()

for f in 0..<totalFrames {
    view.advance(dt)
    ctx.saveGState()
    let nsctx = NSGraphicsContext(cgContext: ctx, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = nsctx
    view.drawScene(ctx, dt: dt)
    NSGraphicsContext.restoreGraphicsState()
    ctx.restoreGState()

    // fade in / fade out so the loop rests on black
    let t = Float(f) * dt
    let total = Float(DURATION_SECONDS)
    var fade: Float = 0
    if t < FADE_SECONDS { fade = 1 - t / FADE_SECONDS }
    else if t > total - FADE_SECONDS { fade = 1 - (total - t) / FADE_SECONDS }
    if fade > 0 {
        ctx.setFillColor(NSColor(calibratedWhite: 0, alpha: CGFloat(min(1, max(0, fade)))).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
    }

    guard let image = ctx.makeImage() else { continue }
    var pb: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pb)
    guard let buf = pb else { continue }
    CVPixelBufferLockBaseAddress(buf, [])
    let dst = CGContext(data: CVPixelBufferGetBaseAddress(buf), width: W, height: H,
                              bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buf),
                              space: colorSpace,
                              bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                              | CGBitmapInfo.byteOrder32Little.rawValue)!
    dst.draw(image, in: CGRect(x: 0, y: 0, width: W, height: H))
    CVPixelBufferUnlockBaseAddress(buf, [])
    while !input.isReadyForMoreMediaData { usleep(2000) }
    adaptor.append(buf, withPresentationTime: CMTime(value: CMTimeValue(f), timescale: FPS))
    written += 1
    if f % 300 == 0 {
        let el = CFAbsoluteTimeGetCurrent() - start
        print("frame \(f)/\(totalFrames)  elapsed \(String(format: "%.1f", el))s")
    }
}

input.markAsFinished()
let sem = DispatchSemaphore(value: 0)
writer.finishWriting { sem.signal() }
sem.wait()
print("done frames=\(written) status=\(writer.status.rawValue) err=\(String(describing: writer.error))")
