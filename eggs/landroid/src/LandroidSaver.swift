// Landroid — macOS port of the Android 17 "Cinnamon Bun" Landroid screensaver (AOSP, Apache-2.0)
// Physics, autopilot, and rendering faithfully ported from:
//   AndroidEasterEggs/eggs/CinnamonBun/src/main/java/com/android_cinnamon_bun/egg/landroid/
// Dream-mode behavior: random universe, autopilot enabled, dynamic zoom.

import Foundation
import ScreenSaver

@objc(LandroidView)
final class LandroidView: ScreenSaverView {
    private var universe: Universe!
    private var cameraZoom: Float = DEFAULT_CAMERA_ZOOM
    private var displayLink: CVDisplayLink?
    private var lastDraw: CFTimeInterval = 0
    private var namer = Namer()

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        animationTimeInterval = 1 / 60
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        let seed = UInt64(Date().timeIntervalSince1970 * 1000) &+ UInt64.random(in: 0...1_000_000)
        universe = Universe(randomSeed: seed, namer: namer)
        universe.initRandom()
        // true randomness for ship start position (DreamUniverse.kt)
        universe.ship.pos = universe.star.pos + V2.makeWithAngleMag(
            Float.random(in: 0..<PI2f),
            Float.random(in: PLANET_ORBIT_RANGE))
    }

    override func startAnimation() {
        super.startAnimation()
        lastDraw = 0
    }

    override func stopAnimation() {
        super.stopAnimation()
    }

    override func animateOneFrame() {
        let now = CACurrentMediaTime()
        if lastDraw == 0 { lastDraw = now }
        var dt = Float(now - lastDraw)
        lastDraw = now
        if dt > 1 { dt = 1 }
        if dt < 0 { dt = 0 }
        universe.dt = dt
        universe.now += dt
        universe.stepSim(dt)
        setNeedsDisplay(bounds)
    }

    override func draw(_ rect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        drawScene(ctx, dt: universe.dt)
    }

    // Advance the simulation by an explicit dt (used by the video renderer).
    func advance(_ dt: Float) {
        universe.dt = dt
        universe.now += dt
        universe.stepSim(dt)
    }

    // Render one frame into an arbitrary context (screen, offscreen bitmap, video frame).
    func drawScene(_ ctx: CGContext, dt: Float) {
        let size = bounds.size
        let u = universe!

        // dynamic zoom (DreamUniverse mode)
        let closest = u.closestPlanet()
        let distToNearestSurf = max(0, (u.ship.pos - closest.pos).mag() - closest.radius * 1.2)
        let targetZoom = min(max(500 / distToNearestSurf, MIN_CAMERA_ZOOM), MAX_CAMERA_ZOOM)
        cameraZoom = expSmooth(cameraZoom, targetZoom, dt: dt, speed: 1.5)

        let w = Float(size.width), h = Float(size.height)
        ctx.setFillColor(LC.Eigengrau.cgColor)
        ctx.fill(bounds)

        // camera follows ship (centered)
        let cam = u.ship.pos
        let zoom = CGFloat(cameraZoom)

        ctx.saveGState()
        ctx.translateBy(x: size.width / 2, y: size.height / 2)
        ctx.scaleBy(x: zoom, y: zoom)
        ctx.translateBy(x: -CGFloat(cam.x), y: -CGFloat(cam.y))

        // Y flip: Android/compose has Y down; flip so orbits look right-side up either way
        // (visually symmetric, no flip needed)

        // grid (from Spaaaace)
        var gridStep: Float = 1000
        while gridStep * cameraZoom < 32 { gridStep *= 10 }
        let halfW = w / 2 / cameraZoom, halfH = h / 2 / cameraZoom
        ctx.setStrokeColor(LC.Eigengrau2.cgColor)
        var gx = (cam.x - halfW / 1).rounded(.down)
        gx = floor((cam.x - halfW) / gridStep) * gridStep
        let gridStroke = 1.5 / cameraZoom
        ctx.setLineWidth(CGFloat(gridStroke))
        var x = gx
        while x < cam.x + halfW {
            ctx.move(to: CGPoint(x: CGFloat(x), y: CGFloat(cam.y - halfH)))
            ctx.addLine(to: CGPoint(x: CGFloat(x), y: CGFloat(cam.y + halfH)))
            x += gridStep
        }
        var y = floor((cam.y - halfH) / gridStep) * gridStep
        while y < cam.y + halfH {
            ctx.move(to: CGPoint(x: CGFloat(cam.x - halfW), y: CGFloat(y)))
            ctx.addLine(to: CGPoint(x: CGFloat(cam.x + halfW), y: CGFloat(y)))
            y += gridStep
        }
        ctx.strokePath()

        // orbits + gravitational fields + planets
        for p in u.planets {
            let drawColor = p.explored ? p.color : LC.Eigengrau4
            if DRAW_ORBITS {
                ctx.setStrokeColor(LC.Eigengrau3.cgColor)
                ctx.setLineWidth(CGFloat(1 / cameraZoom))
                ctx.strokeEllipse(in: CGRect(
                    x: CGFloat(p.orbitCenter.x - p.pos.distance(p.orbitCenter)),
                    y: CGFloat(p.orbitCenter.y - p.pos.distance(p.orbitCenter)),
                    width: CGFloat(2 * p.pos.distance(p.orbitCenter)),
                    height: CGFloat(2 * p.pos.distance(p.orbitCenter))))
            }
            if DRAW_GRAVITATIONAL_FIELDS {
                drawGravField(ctx, planet: p, now: u.now, zoom: cameraZoom)
            }
            ctx.setFillColor(LC.Eigengrau.cgColor)
            fillCircle(ctx, p.pos, p.radius)
            ctx.setStrokeColor(drawColor.cgColor)
            ctx.setLineWidth(CGFloat(2 / cameraZoom))
            strokeCircle(ctx, p.pos, p.radius)
        }

        // star
        drawStar(ctx, star: u.star, now: u.now, zoom: cameraZoom)

        // sparks
        for s in u.sparks {
            let life = 1 - s.fuse.lifetime / s.ttl
            switch s.style {
            case .dot:
                ctx.setFillColor(s.color.cgColor)
                fillCircle(ctx, s.pos, s.size)
            case .ring:
                var c = s.color.cgColor.copy(alpha: CGFloat(1 - life))
                ctx.setStrokeColor(c ?? NSColor.white.cgColor)
                ctx.setLineWidth(CGFloat(1 / cameraZoom))
                let r = exp(lerp(s.size, 3 * s.size, life)) - 1
                strokeCircle(ctx, s.pos, r)
                c = nil
            case .line:
                break
            }
        }

        // track (green trail)
        if u.ship.track.positions.count > 1 {
            ctx.setStrokeColor(LC.Track.cgColor)
            ctx.setLineWidth(CGFloat(max(1, 1 / cameraZoom)))
            let pts = u.ship.track.positions
            ctx.beginPath()
            ctx.move(to: pt(pts[0]))
            for i in 1..<pts.count { ctx.addLine(to: pt(pts[i])) }
            ctx.strokePath()
        }

        // autopilot target reticle
        if let ap = u.ship.autopilot, let target = ap.target {
            let color = LC.Autopilot.withAlphaComponent(0.5).cgColor
            ctx.saveGState()
            ctx.translateBy(x: CGFloat(target.pos.x), y: CGFloat(target.pos.y))
            ctx.rotate(by: CGFloat(u.now * PI2f / 10))
            ctx.setStrokeColor(color)
            ctx.setLineWidth(CGFloat(1 / cameraZoom))
            let r = target.radius + ap.brakingDistance
            ctx.addEllipse(in: CGRect(x: CGFloat(-r), y: CGFloat(-r), width: CGFloat(2 * r), height: CGFloat(2 * r)))
            ctx.strokePath()
            // polygon of 15 sides
            let poly = createPolygonPath(target.radius + ap.brakingDistance, 15)
            ctx.addPath(poly)
            ctx.strokePath()
            ctx.restoreGState()
        }

        // ship
        drawShip(ctx, ship: u.ship, zoom: cameraZoom)

        // flag on landing site
        if let landing = u.landing {
            let v = landing.planet.pos + V2.makeWithAngleMag(landing.angle, landing.planet.radius)
            ctx.saveGState()
            ctx.translateBy(x: CGFloat(v.x), y: CGFloat(v.y))
            ctx.rotate(by: CGFloat(-landing.angle + PIf / 2))
            ctx.setStrokeColor(LC.Flag.cgColor)
            ctx.setLineWidth(CGFloat(2 / cameraZoom))
            let hh: Float = 80
            ctx.beginPath()
            ctx.move(to: .zero)
            ctx.addLine(to: CGPoint(x: CGFloat(hh), y: 0))
            ctx.addLine(to: CGPoint(x: CGFloat(hh * 0.875), y: CGFloat(hh * 0.25)))
            ctx.addLine(to: CGPoint(x: CGFloat(hh * 0.75), y: 0))
            ctx.closePath()
            ctx.strokePath()
            ctx.restoreGState()
        }

        ctx.restoreGState()

        // ---- cockpit / telemetry overlay (Telemetry composable from MainActivity.kt) ----
        drawTelemetry(ctx)
    }

    private func pt(_ v: V2) -> CGPoint { CGPoint(x: CGFloat(v.x), y: CGFloat(v.y)) }

    private func fillCircle(_ ctx: CGContext, _ c: V2, _ r: Float) {
        ctx.fillEllipse(in: CGRect(x: CGFloat(c.x - r), y: CGFloat(c.y - r),
                                   width: CGFloat(2 * r), height: CGFloat(2 * r)))
    }
    private func strokeCircle(_ ctx: CGContext, _ c: V2, _ r: Float) {
        ctx.strokeEllipse(in: CGRect(x: CGFloat(c.x - r), y: CGFloat(c.y - r),
                                     width: CGFloat(2 * r), height: CGFloat(2 * r)))
    }
    private func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float { a + (b - a) * t }

    private func drawGravField(_ ctx: CGContext, planet: Planet, now: Float, zoom: Float) {
        let rings = 10
        for i in 0..<rings {
            let force = lerp(2000, 0.01, (Float(i) - now.truncatingRemainder(dividingBy: 1)) / Float(rings))
            let r = (GRAVITATION * planet.mass * SPACECRAFT_MASS / force).squareRoot()
            let alpha = lerp(0.75, 0.1, Float(i) / Float(rings))
            ctx.setStrokeColor(NSColor(calibratedRed: 1, green: 0, blue: 0, alpha: CGFloat(alpha)).cgColor)
            ctx.setLineWidth(CGFloat(2 / zoom))
            strokeCircle(ctx, planet.pos, r)
        }
    }

    private func drawStar(_ ctx: CGContext, star: Star, now: Float, zoom: Float) {
        ctx.saveGState()
        ctx.translateBy(x: CGFloat(star.pos.x), y: CGFloat(star.pos.y))
        if DRAW_STAR_GRAVITATIONAL_FIELDS { drawGravField(ctx, planet: star, now: now, zoom: zoom) }
        ctx.setFillColor(star.color.cgColor)
        fillCircle(ctx, .zero, star.radius)
        // two rotating star outlines
        for (animDiv, r1, r2, pts, dir) in [(Float(23), Float(80), Float(250), STAR_POINTS, 1),
                                            (Float(19), Float(20), Float(200), STAR_POINTS + 1, -1)] {
            ctx.saveGState()
            ctx.rotate(by: CGFloat(Float(dir) * now / animDiv * PI2f))
            let path = createStarPath(star.radius + r1, star.radius + r2, pts)
            ctx.addPath(path)
            ctx.setStrokeColor(star.color.cgColor)
            ctx.setLineWidth(CGFloat(3 / zoom))
            ctx.setLineJoin(.round)
            ctx.setLineCap(.round)
            ctx.strokePath()
            ctx.restoreGState()
        }
        ctx.restoreGState()
    }

    private func drawShip(_ ctx: CGContext, ship: Spacecraft, zoom: Float) {
        ctx.saveGState()
        ctx.translateBy(x: CGFloat(ship.pos.x), y: CGFloat(ship.pos.y))
        ctx.rotate(by: CGFloat(ship.angle))
        // fill (fauxpaque)
        ctx.setFillColor(LC.Eigengrau.cgColor)
        ctx.addPath(spaceshipPath)
        ctx.fillPath()
        // outline
        ctx.setStrokeColor((ship.transit ? NSColor.black : NSColor.white).cgColor)
        ctx.setLineWidth(CGFloat(2 / zoom))
        ctx.addPath(spaceshipPath)
        ctx.strokePath()
        // thrust
        if ship.thrust != V2.zero {
            ctx.setStrokeColor(NSColor(calibratedRed: 1, green: 0x88 / 255, blue: 0, alpha: 1).cgColor)
            ctx.setLineWidth(CGFloat(2 / zoom))
            ctx.setLineJoin(.round)
            ctx.addPath(thrustPath)
            ctx.strokePath()
        }
        ctx.restoreGState()
    }

    // MARK: - Cockpit telemetry (port of Telemetry() in MainActivity.kt)

    private var uiAppearAt: Float = -1
    private var uiFlickerRng = SeededGenerator(seed: 0x1A2D2017)

    private func systemDesignation() -> String { "CB-\(universe.randomSeed % 100_000)" }

    private func capitalize(_ s: String) -> String {
        guard let f = s.first else { return s }
        return String(f).uppercased() + s.dropFirst().lowercased()
    }

    /// CRT-style flicker fade: each frame is fully on with probability = progress.
    private func flickerAlpha(progress: Float) -> CGFloat {
        if progress <= 0 { return 0 }
        if progress >= 1 { return 1 }
        return uiFlickerRng.nextFloat() < progress ? 1 : 0
    }

    private func drawTelemetry(_ ctx: CGContext) {
        let u = universe!
        if uiAppearAt < 0 { uiAppearAt = 0 }
        let elapsed = u.now - uiAppearAt

        let W = Float(bounds.width), H = Float(bounds.height)
        let scale = min(max(H / 900, 0.7), 1.8)
        let fontSize = CGFloat(12 * scale)
        let catalogSize = CGFloat(9 * scale)
        let pad = CGFloat(6 * scale)
        let lineH = fontSize * 1.05
        let catalogLineH = catalogSize * 1.15
        // bottom panel: appears 1s after start
        let bottomAlpha = flickerAlpha(progress: (elapsed - 1) / 1)
        if bottomAlpha > 0 {
            var block: [(String, NSColor)] = []
            if let ap = u.ship.autopilot, ap.enabled {
                block.append((ap.telemetry, LC.Autopilot))
            }
            block.append((consoleText(), LC.Console))

            var totalLines = 0
            for (t, _) in block { totalLines += t.split(separator: "\n", omittingEmptySubsequences: false).count }
            totalLines += block.count - 1 // one blank line between blocks

            let x = pad   // telemetry sits in the bottom-left corner
            var topY = pad + CGFloat(totalLines) * lineH
            for (text, color) in block {
                drawMonoText(ctx, text, x: x, topY: topY, size: fontSize, color: color,
                             alpha: bottomAlpha, lineHeight: lineH)
                let n = text.split(separator: "\n", omittingEmptySubsequences: false).count + 1
                topY -= CGFloat(n) * lineH
            }
        }

        // catalogue panel: appears 2s after start
        let topAlpha = flickerAlpha(progress: (elapsed - 2) / 1)
        if topAlpha > 0 {
            drawMonoText(ctx, catalogText(), x: pad, topY: CGFloat(H) - pad,
                         size: catalogSize, color: LC.Console, alpha: topAlpha,
                         lineHeight: catalogLineH)
        }
    }

    func consoleText() -> String {
        let u = universe!
        let ship = u.ship!
        let closest = u.closestPlanet()
        let distToClosest = ((closest.pos - ship.pos).mag() - closest.radius)
        var lines: [String] = []
        if let landing = ship.landing {
            lines.append("LND: \(landing.planet.name.uppercased())")
            lines.append("JOB: \(landing.text.uppercased())")
        } else if distToClosest < 10_000 {
            lines.append("ALT: \(Int(distToClosest))")
        }
        lines.append(String(format: "THR: %.0f%%", ship.thrust.mag() * 100))
        lines.append(String(format: "POS: <%+7.0f,%+7.0f>", ship.pos.x, ship.pos.y))
        lines.append(String(format: "VEL: %.0f", ship.velocity.mag()))
        return lines.joined(separator: "\n")
    }

    func catalogText() -> String {
        let u = universe!
        let explored = u.planets.filter { $0.explored }
        var lines: [String] = [
            "  STAR: \(u.star.name) (\(systemDesignation()))",
            " CLASS: \(starClassName(u.star.cls))",
            "RADIUS: \(Int(u.star.radius))",
            String(format: "  MASS: %.3g", u.star.mass),
            "BODIES: \(explored.count) / \(u.planets.count)",
            "",
        ]
        for p in explored {
            lines.append("  BODY: \(p.name)")
            lines.append("  TYPE: \(capitalize(p.description))")
            lines.append("  ATMO: \(capitalize(p.atmosphere))")
            lines.append(" FAUNA: \(capitalize(p.fauna))")
            lines.append(" FLORA: \(capitalize(p.flora))")
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private func starClassName(_ cls: StarClass) -> String {
        switch cls {
        case .O: return "O"
        case .B: return "B"
        case .A: return "A"
        case .F: return "F"
        case .G: return "G"
        case .K: return "K"
        case .M: return "M"
        }
    }

    private func drawMonoText(_ ctx: CGContext, _ text: String, x: CGFloat, topY: CGFloat,
                             size: CGFloat, color: NSColor, alpha: CGFloat, lineHeight: CGFloat) {
        let font = NSFont.monospacedSystemFont(ofSize: size, weight: .medium)
        let ascent = CGFloat(CTFontGetAscent(font as CTFont))
        let col = color.withAlphaComponent(color.alphaComponent * alpha)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: col,
            .kern: size * (1.0 / 12.0),
        ]
        ctx.saveGState()
        ctx.setShouldSmoothFonts(false)
        var baseline = topY - ascent
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            if !line.isEmpty {
                let attr = NSAttributedString(string: line, attributes: attrs)
                let ctLine = CTLineCreateWithAttributedString(attr)
                ctx.textPosition = CGPoint(x: x, y: baseline)
                CTLineDraw(ctLine, ctx)
            }
            baseline -= lineHeight
        }
        ctx.restoreGState()
    }

    override var hasConfigureSheet: Bool { false }
    override var configureSheet: NSWindow? { nil }
}


// MARK: - Math helpers (Vec2.kt, Maths.kt, Randomness.kt)

let PIf = Float.pi
let PI2f = Float.pi * 2

struct V2: Equatable {
    var x: Float, y: Float
    static let zero = V2(x: 0, y: 0)
    static func + (a: V2, b: V2) -> V2 { V2(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: V2, b: V2) -> V2 { V2(x: a.x - b.x, y: a.y - b.y) }
    static func * (a: V2, f: Float) -> V2 { V2(x: a.x * f, y: a.y * f) }
    static func * (f: Float, a: V2) -> V2 { V2(x: a.x * f, y: a.y * f) }
    static func / (a: V2, f: Float) -> V2 { V2(x: a.x / f, y: a.y / f) }
    static prefix func - (a: V2) -> V2 { V2(x: -a.x, y: -a.y) }
    func mag() -> Float { (x * x + y * y).squareRoot() }
    func distance(_ o: V2) -> Float { (self - o).mag() }
    func angle() -> Float { atan2(y, x) }
    func dot(_ o: V2) -> Float { x * o.x + y * o.y }
    static func makeWithAngleMag(_ a: Float, _ m: Float) -> V2 { V2(x: m * cos(a), y: m * sin(a)) }
}

func expSmooth(_ current: Float, _ target: Float, dt: Float, speed: Float) -> Float {
    current + (target - current) * (1 - exp(-dt * speed))
}

func hsv(_ h: Float, _ s: Float, _ v: Float) -> NSColor {
    NSColor(colorSpace: .genericRGB, hue: CGFloat(h / 360), saturation: CGFloat(s),
            brightness: CGFloat(v), alpha: 1)
}

// MARK: - Colors (Colors.kt)

enum LC {
    static let Eigengrau = NSColor(calibratedRed: 0x16 / 255, green: 0x16 / 255, blue: 0x1D / 255, alpha: 1)
    static let Eigengrau2 = NSColor(calibratedRed: 0x29 / 255, green: 0x29 / 255, blue: 0x36 / 255, alpha: 1)
    static let Eigengrau3 = NSColor(calibratedRed: 0x3C / 255, green: 0x3C / 255, blue: 0x4F / 255, alpha: 1)
    static let Eigengrau4 = NSColor(calibratedRed: 0xA7 / 255, green: 0xA7 / 255, blue: 0xCA / 255, alpha: 1)
    static let Autopilot = NSColor(calibratedRed: 0x42 / 255, green: 0x85 / 255, blue: 0xF4 / 255, alpha: 1)
    static let Console = NSColor(calibratedRed: 0xB7 / 255, green: 0xB7 / 255, blue: 0xFF / 255, alpha: 1)
    static let Track = NSColor(calibratedRed: 0x34 / 255, green: 0xA8 / 255, blue: 0x53 / 255, alpha: 1)
    static let Flag = NSColor(calibratedRed: 0xC6 / 255, green: 0xFF / 255, blue: 0x00 / 255, alpha: 1)
}

// MARK: - Physics (Physics.kt, Universe.kt)

let UNIVERSE_RANGE: Float = 200_000
let STAR_RADIUS_RANGE: ClosedRange<Float> = 1_000...8_000
let PLANET_RADIUS_RANGE: ClosedRange<Float> = 50...2_000
let PLANET_ORBIT_RANGE: ClosedRange<Float> = (STAR_RADIUS_RANGE.upperBound * 2)...(UNIVERSE_RANGE * 0.75)
let GRAVITATION: Float = 1e-2
let KEPLER_CONSTANT: Float = 50
let PLANETARY_DENSITY: Float = 2.5
let STELLAR_DENSITY: Float = 0.5
let SPACECRAFT_MASS: Float = 10
let CRAFT_SPEED_LIMIT: Float = 5_000
let MAIN_ENGINE_ACCEL: Float = 1_000
let LAUNCH_MECO: Float = 2
let LANDING_REMOVAL_TIME: Float = 60 * 15
let TRACK_LENGTH = 10_000
let STAR_POINTS = 31

struct Fuse {
    var lifetime: Float
    init(_ l: Float) { lifetime = l }
    mutating func update(_ dt: Float) { lifetime -= dt }
    var canBeRemoved: Bool { lifetime < 0 }
}

class Body {
    var pos = V2.zero
    var opos = V2.zero
    var velocity = V2.zero
    var mass: Float = 0
    var angle: Float = 0
    var radius: Float = 0
    var collides = true
    var name = "Unknown"
    var removed = false

    func update(_ dt: Float) {
        guard dt > 0 else { return }
        opos = pos
        pos = pos + velocity * dt
    }
    func postUpdate(_ dt: Float) {
        guard dt > 0 else { return }
        velocity = (pos - opos) / dt
    }
}

enum StarClass: CaseIterable {
    case O, B, A, F, G, K, M
    var color: NSColor {
        switch self {
        case .O: return NSColor(calibratedRed: 0x66 / 255, green: 0x66 / 255, blue: 0xFF / 255, alpha: 1)
        case .B: return NSColor(calibratedWhite: 0xCC / 255, alpha: 1)
        case .A: return NSColor(calibratedWhite: 0xEE / 255, alpha: 1)
        case .F: return .white
        case .G: return NSColor(calibratedRed: 1, green: 1, blue: 0x66 / 255, alpha: 1)
        case .K: return NSColor(calibratedRed: 0xFF / 255, green: 0xCC / 255, blue: 0x33 / 255, alpha: 1)
        case .M: return NSColor(calibratedRed: 1, green: 0x88 / 255, blue: 0, alpha: 1)
        }
    }
}

class Planet: Body {
    let orbitCenter: V2
    let orbitRadius: Float
    var speed: Float
    var color: NSColor = .white
    var explored = false
    var description = ""
    var atmosphere = ""
    var flora = ""
    var fauna = ""
    init(orbitCenter: V2, radius: Float, pos: V2, speed: Float) {
        self.orbitCenter = orbitCenter
        self.speed = speed
        self.orbitRadius = pos.distance(orbitCenter)
        super.init()
        self.radius = radius
        self.pos = pos
        mass = 4 / 3 * PIf * pow(radius, 3) * PLANETARY_DENSITY
    }
    override func update(_ dt: Float) {
        let orbitAngle = (pos - orbitCenter).angle()
        velocity = V2.makeWithAngleMag(orbitAngle + PIf / 2, speed)
        super.update(dt)
    }
    override func postUpdate(_ dt: Float) {
        let orbitAngle = (pos - orbitCenter).angle()
        pos = orbitCenter + V2.makeWithAngleMag(orbitAngle, orbitRadius)
        super.postUpdate(dt)
    }
}

class Star: Planet {
    let cls: StarClass
    var anim: Float = 0
    init(cls: StarClass, radius: Float) {
        self.cls = cls
        super.init(orbitCenter: .zero, radius: radius, pos: .zero, speed: 0)
        pos = .zero
        mass = 4 / 3 * PIf * pow(radius, 3) * STELLAR_DENSITY
        color = cls.color
        collides = false
    }
    override func update(_ dt: Float) { anim += dt }
    override func postUpdate(_ dt: Float) {}
}

class Spark: Body {
    enum Style { case line, dot, ring }
    let style: Style
    let color: NSColor
    let size: Float
    let ttl: Float
    var opos2 = V2.zero // old position for line sparks
    var fuse: Fuse
    init(ttl: Float, style: Style, color: NSColor, size: Float) {
        self.ttl = ttl
        self.style = style
        self.color = color
        self.size = size
        self.fuse = Fuse(ttl)
        super.init()
        name = "Spark"
        collides = false
    }
    override func update(_ dt: Float) {
        super.update(dt)
        fuse.update(dt)
    }
}

class Track {
    var positions: [V2] = []
    private var capacity = 0
    func add(_ p: V2) {
        positions.append(p)
        if positions.count >= TRACK_LENGTH {
            positions.removeFirst(2)
        }
        _ = capacity
    }
}

class Spacecraft: Body {
    var thrust = V2.zero
    var launchClock: Float = 0
    var transit = false
    let track = Track()
    var landing: Landing?
    var autopilot: Autopilot?
    override init() {
        super.init()
        mass = SPACECRAFT_MASS
        radius = 12
    }
    override func update(_ dt: Float) { update(dt, now: 0) }
    func update(_ dt: Float, now: Float) {
        let thrustMag = thrust.mag()
        if thrustMag > 0 {
            var deltaV = MAIN_ENGINE_ACCEL * dt
            if let landing = landing {
                if launchClock == 0 { launchClock = now + 1 }
                if now > launchClock {
                    landing.ship = nil
                    self.landing = nil
                } else {
                    deltaV = 0
                }
            }
            velocity = velocity + V2.makeWithAngleMag(angle, deltaV)
        } else {
            if launchClock != 0 { launchClock = 0 }
        }
        if velocity.mag() > CRAFT_SPEED_LIMIT {
            velocity = V2.makeWithAngleMag(velocity.angle(), CRAFT_SPEED_LIMIT)
        }
        super.update(dt)
    }
    override func postUpdate(_ dt: Float) {
        super.postUpdate(dt)
        track.add(pos)
    }
}

class Landing {
    weak var ship: Spacecraft?
    let planet: Planet
    let angle: Float
    let text: String
    var fuse: Fuse
    init(ship: Spacecraft, planet: Planet, angle: Float, text: String = "") {
        self.ship = ship
        self.planet = planet
        self.angle = angle
        self.text = text
        self.fuse = Fuse(LANDING_REMOVAL_TIME)
    }
    func solve(_ dt: Float) {
        if let ship = ship {
            let desiredPos = planet.pos + V2.makeWithAngleMag(angle, ship.radius + planet.radius)
            ship.pos = ship.pos * 0.5 + desiredPos * 0.5
            ship.angle = angle
        }
        fuse.update(dt)
    }
}

// MARK: - Autopilot (Autopilot.kt)

final class Autopilot {
    let BRAKING_TIME: Float = 5
    let SIGHTSEEING_TIME: Float = 15
    let LAUNCH_THRUST_TIME: Float = 5
    let STRATEGY_MIN_TIME: Float = 0.5

    weak var shipRef: Spacecraft?
    let universe: Universe
    var enabled = false
    var target: Planet?
    var landingAltitude: Float = 0
    var nextStrategyTime: Float = 0
    var brakingDistance: Float = 0
    var leadingPos = V2.zero

    init(ship: Spacecraft, universe: Universe) {
        self.shipRef = ship
        self.universe = universe
    }

    func update(_ dt: Float) {
        guard enabled, let ship = shipRef else { return }
        if universe.now < nextStrategyTime { return }
        let currentStrategy = strategy

        if ship.landing != nil {
            if target != nil {
                strategy = "LANDED"
                target = nil
                landingAltitude = 0
                nextStrategyTime = universe.now + SIGHTSEEING_TIME
            } else {
                ship.thrust = V2.makeWithAngleMag(ship.angle, 1)
                strategy = "LAUNCHING"
                nextStrategyTime = universe.now + LAUNCH_THRUST_TIME
            }
        } else {
            if target == nil {
                target = universe.planets
                    .sorted { ($0.pos - ship.pos).mag() < ($1.pos - ship.pos).mag() }
                    .first { !$0.explored }
                brakingDistance = 0
                if target == nil { target = universe.planets.randomElement() }
            }
            if let target = self.target {
                let shipV = ship.velocity
                let targetV = target.velocity
                let targetVector = target.pos - ship.pos
                let altitude = targetVector.mag() - target.radius
                landingAltitude = min(target.radius, 100)
                let relativeV = shipV - targetV
                let projection = relativeV.dot(targetVector * (1 / targetVector.mag()))
                let relativeSpeed = relativeV.mag() * (projection >= 0 ? 1 : -1)
                let timeToTarget = relativeSpeed != 0 ? altitude / relativeSpeed : 1_000
                let newBrakingDistance = BRAKING_TIME * (relativeSpeed > 0 ? relativeSpeed : MAIN_ENGINE_ACCEL)
                brakingDistance = expSmooth(brakingDistance, newBrakingDistance, dt: universe.dt, speed: 5)

                leadingPos = target.pos +
                    V2.makeWithAngleMag(target.velocity.angle(),
                                        min(altitude / 2, target.velocity.mag()))
                let leadingVector = leadingPos - ship.pos

                if altitude < landingAltitude {
                    strategy = "LANDING"
                    ship.angle = (ship.pos - target.pos).angle()
                    ship.thrust = V2.zero
                } else if relativeSpeed < 0 || altitude > brakingDistance {
                    strategy = "CHASING"
                    ship.angle = leadingVector.angle()
                    ship.thrust = V2.makeWithAngleMag(ship.angle, 1)
                } else {
                    strategy = "APPROACHING"
                    ship.angle = (-ship.velocity).angle()
                    let decel = relativeSpeed / timeToTarget
                    let decelThrust = decel / MAIN_ENGINE_ACCEL * 0.9
                    ship.thrust = V2.makeWithAngleMag(ship.angle, decelThrust)
                }
            }
            if strategy != currentStrategy {
                nextStrategyTime = universe.now + STRATEGY_MIN_TIME
            }
        }
    }
    var strategy = "NONE"

    var telemetry: String {
        guard enabled else { return "" }
        let tgt = target?.name.uppercased() ?? "SELECTING..."
        return "---- AUTOPILOT ENGAGED ----\nTGT: \(tgt)\nEXE: \(strategy)"
    }
}

// MARK: - Universe (Universe.kt) + Simulator (Physics.kt)

final class Universe {
    var now: Float = 0
    var dt: Float = 0
    let randomSeed: UInt64
    var rng: SeededGenerator
    var namer: Namer
    var star: Star!
    var ship: Spacecraft!
    var planets: [Planet] = []
    var sparks: [Spark] = []
    var landing: Landing?
    let ringfenceRadius: Float = UNIVERSE_RANGE
    let follow: Body?

    init(randomSeed: UInt64, namer: Namer) {
        self.randomSeed = randomSeed
        self.rng = SeededGenerator(seed: randomSeed)
        self.namer = namer
        self.follow = nil
    }

    func initRandom() {
        let systemName = namer.nameSystem(&rng)
        star = Star(cls: StarClass.allCases.randomElement(using: &rng)!,
                    radius: rng.nextFloat(in: STAR_RADIUS_RANGE))
        star.name = systemName
        let numPlanets = rng.next(1...10)
        for _ in 0..<numPlanets {
            let radius = rng.nextFloat(in: PLANET_RADIUS_RANGE)
            let orbitRadius = PLANET_ORBIT_RANGE.lowerBound +
                rng.nextFloat() * (PLANET_ORBIT_RANGE.upperBound - PLANET_ORBIT_RANGE.lowerBound)
            let period = sqrt(pow(orbitRadius, 3) / star.mass) * KEPLER_CONSTANT
            let speed = 2 * PIf * orbitRadius / period
            let hue = radius.truncatingRemainder(dividingBy: 360)
            let p = Planet(orbitCenter: star.pos, radius: radius,
                           pos: star.pos + V2.makeWithAngleMag(rng.nextFloat() * PI2f, orbitRadius),
                           speed: speed)
            p.color = hsv(hue, 0.75, 1)
            p.name = systemName
            p.description = namer.describePlanet(&rng)
            p.atmosphere = namer.describeAtmo(&rng)
            p.flora = namer.describeLife(&rng)
            p.fauna = namer.describeLife(&rng)
            planets.append(p)
        }
        planets.sort { $0.pos.distance(star.pos) < $1.pos.distance(star.pos) }
        planets.enumerated().forEach { $1.name = "\(systemName) \($0 + 1)" }

        ship = Spacecraft()
        ship.pos = star.pos + V2.makeWithAngleMag(rng.nextFloat() * PI2f,
            rng.nextFloat(in: PLANET_ORBIT_RANGE))
        ship.angle = rng.nextFloat() * PI2f

        let autopilot = Autopilot(ship: ship, universe: self)
        ship.autopilot = autopilot
        autopilot.enabled = true
    }

    func closestPlanet() -> Planet {
        let bodies = (planets as [Planet]) + [star!]
        return bodies.min { ($0.pos - ship.pos).mag() < ($1.pos - ship.pos).mag() }!
    }

    func stepSim(_ dt: Float) {
        simulate(dt)
    }

    func step(nanos: UInt64) {
        if lastNanos == 0 { lastNanos = nanos; return }
        var d = Float(nanos - lastNanos) / 1_000_000_000
        lastNanos = nanos
        if d > 1 { d = 1 }
        if d <= 0 { return }
        dt = d
        now += d
        simulate(d)
    }
    private var lastNanos: UInt64 = 0

    private func simulate(_ dt: Float) {
        let ship = self.ship!

        // gravity (updateAll override)
        ship.transit = false
        for planet in (planets as [Planet]) + [star!] {
            let vector = planet.pos - ship.pos
            let d = vector.mag()
            if d < planet.radius {
                if planet is Star { ship.transit = true }
            } else if now > ship.launchClock + LAUNCH_MECO {
                ship.velocity = ship.velocity +
                    V2.makeWithAngleMag(vector.angle(), GRAVITATION * (ship.mass * planet.mass) / (d * d)) * dt
            }
        }

        // autopilot
        ship.autopilot?.update(dt)

        // update bodies
        for p in planets { p.update(dt) }
        star.update(dt)
        ship.update(dt, now: now)
        for s in sparks { s.update(dt) }

        // constraints (solveAll override: landing check)
        if ship.landing == nil {
            let planet = closestPlanet()
            if planet.collides {
                let d = (ship.pos - planet.pos).mag() - ship.radius - planet.radius
                let a = (ship.pos - planet.pos).angle()
                if d < 0 {
                    let vDiff = (ship.velocity - planet.velocity).mag()
                    let aDiff = abs(ship.angle - a)
                    _ = vDiff
                    if aDiff < PIf / 4 {
                        let landing = Landing(ship: ship, planet: planet, angle: a, text: namer.describeActivity(&rng, planet))
                        if ship.thrust != V2.zero { ship.thrust = V2.zero }
                        ship.landing = landing
                        ship.velocity = planet.velocity
                        self.landing = landing
                        planet.explored = true
                    } else {
                        let impact = planet.pos + V2.makeWithAngleMag(a, planet.radius)
                        ship.pos = planet.pos + V2.makeWithAngleMag(a, planet.radius + ship.radius - d)
                        for _ in 1...10 {
                            let spark = Spark(ttl: rng.nextFloat(in: 0.5...2), style: .dot,
                                              color: .white, size: 1)
                            spark.pos = impact + V2.makeWithAngleMag(
                                rng.nextFloat(in: 0...(2 * PIf)), rng.nextFloat(in: 0.1...0.5))
                            spark.velocity = ship.velocity * 0.8 + V2.makeWithAngleMag(
                                rng.nextFloat(in: 0...(2 * PIf)), rng.nextFloat(in: 0.1...0.5))
                            sparks.append(spark)
                        }
                    }
                }
            }
        }

        // ringfence constraint
        if (ship.pos.mag() + ship.radius) > ringfenceRadius {
            ship.pos = V2.makeWithAngleMag(ship.pos.angle(), ringfenceRadius - ship.radius)
        }

        // landing constraint
        landing?.solve(dt)
        if let l = landing, l.fuse.canBeRemoved || l.ship == nil {
            if l.ship != nil { l.ship?.landing = nil }
            landing = nil
        }

        // postUpdate
        for p in planets { p.postUpdate(dt) }
        ship.postUpdate(dt)

        // exhaust sparks (Spacecraft.postUpdate)
        let mag = ship.thrust.mag()
        if rng.nextFloat() < mag {
            let spark = Spark(ttl: rng.nextFloat(in: 0.5...1), style: .ring,
                              color: NSColor(calibratedWhite: 1, alpha: 0x40 / 255), size: 1)
            spark.pos = ship.pos
            spark.velocity = ship.velocity + V2.makeWithAngleMag(
                ship.angle + rng.nextFloat(in: -0.2...0.2), -MAIN_ENGINE_ACCEL * mag * 10 * dt)
            sparks.append(spark)
        }

        // remove dead sparks
        sparks.removeAll { $0.fuse.canBeRemoved }
    }
}

// MARK: - Namer (Namer.kt + wordlists.swift)

struct Bag<T> {
    private var remaining: [T]
    private var next: Int
    init(_ items: [T]) {
        remaining = items
        next = items.count
    }
    mutating func pull(_ rng: inout SeededGenerator) -> T {
        if next >= remaining.count {
            remaining.shuffle(using: &rng)
            next = 0
        }
        defer { next += 1 }
        return remaining[next]
    }
}

struct RandomTable<T> {
    private let pairs: [(Float, T)]
    private let total: Float
    init(_ pairs: [(Float, T)]) {
        self.pairs = pairs
        self.total = pairs.reduce(0) { $0 + $1.0 }
    }
    func roll(_ rng: inout SeededGenerator) -> T {
        var x = rng.nextFloat(in: 0...total)
        for (weight, result) in pairs {
            x -= weight
            if x < 0 { return result }
        }
        return pairs.last!.1
    }
}

let SUFFIX_PROB: Float = 0.75
let LETTER_PROB: Float = 0.3
let NUMBER_PROB: Float = 0.3
let RARE_PROB: Float = 0.05

struct Namer {
    private var planetDescriptors: Bag<String>
    private var lifeDescriptors: Bag<String>
    private var anyDescriptors: Bag<String>
    private var atmoDescriptors: Bag<String>
    private var planetTypes: Bag<String>
    private var constellations: Bag<String>
    private var constellationsRare: Bag<String>
    private var suffixes: Bag<String>
    private var suffixesRare: Bag<String>
    private var activities: Bag<String>

    init() {
        planetDescriptors = Bag(cinnamon_bun_planet_descriptors)
        lifeDescriptors = Bag(cinnamon_bun_life_descriptors)
        anyDescriptors = Bag(cinnamon_bun_any_descriptors)
        atmoDescriptors = Bag(cinnamon_bun_atmo_descriptors)
        planetTypes = Bag(cinnamon_bun_planet_types)
        constellations = Bag(cinnamon_bun_constellations)
        constellationsRare = Bag(cinnamon_bun_constellations_rare)
        suffixes = Bag(cinnamon_bun_star_suffixes)
        suffixesRare = Bag(cinnamon_bun_star_suffixes_rare)
        activities = Bag(cinnamon_bun_activities)
    }

    mutating func nameSystem(_ rng: inout SeededGenerator) -> String {
        var parts = ""
        let ctable = RandomTable<Float>([(RARE_PROB, 0), (1 - RARE_PROB, 1)])
        if ctable.roll(&rng) == 0 { parts += constellationsRare.pull(&rng) }
        else { parts += constellations.pull(&rng) }
        if rng.nextFloat() <= SUFFIX_PROB {
            parts += rollDelimiter(&rng)
            parts += rollSuffix(&rng)
            if rng.nextFloat() <= RARE_PROB { parts += " " + suffixesRare.pull(&rng) }
        }
        if rng.nextFloat() <= LETTER_PROB {
            parts += rollDelimiter(&rng)
            parts += String(UnicodeScalar(65 + rng.next(0..<26))!)
            if rng.nextFloat() <= RARE_PROB { parts += rollDelimiter(&rng) }
        }
        if rng.nextFloat() <= NUMBER_PROB {
            parts += rollDelimiter(&rng)
            parts += String(rng.next(2..<5039))
        }
        return parts
    }

    private mutating func rollDelimiter(_ rng: inout SeededGenerator) -> String {
        let table = RandomTable<String>([(15, " "), (3, "-"), (1, "_"), (1, "/"), (1, "."),
                                         (1, "*"), (1, "^"), (1, "#"), (0.1, "(^*!%@##!!")])
        return table.roll(&rng)
    }
    private mutating func rollSuffix(_ rng: inout SeededGenerator) -> String {
        let table = RandomTable<Float>([(RARE_PROB, 0), (1 - RARE_PROB, 1)])
        if table.roll(&rng) == 0 { return suffixesRare.pull(&rng) }
        return suffixes.pull(&rng)
    }

    // MARK: catalogue text (Namer.kt: describePlanet / describeAtmo / describeLife / describeActivity)

    private mutating func pullDescriptor(_ rng: inout SeededGenerator, table: Int) -> String {
        // weighted table: 0.75 specific descriptors, 0.25 generic "any" descriptors
        let roll = RandomTable<Float>([(0.75, 0), (0.25, 1)]).roll(&rng)
        if roll == 0 {
            switch table {
            case 0: return planetDescriptors.pull(&rng)
            case 1: return lifeDescriptors.pull(&rng)
            default: return atmoDescriptors.pull(&rng)
            }
        }
        return anyDescriptors.pull(&rng)
    }

    mutating func describePlanet(_ rng: inout SeededGenerator) -> String {
        pullDescriptor(&rng, table: 0) + " " + planetTypes.pull(&rng)
    }
    mutating func describeLife(_ rng: inout SeededGenerator) -> String {
        pullDescriptor(&rng, table: 1)
    }
    mutating func describeAtmo(_ rng: inout SeededGenerator) -> String {
        pullDescriptor(&rng, table: 2)
    }

    mutating func describeActivity(_ rng: inout SeededGenerator, _ target: Planet?) -> String {
        var activity = activities.pull(&rng)
        let flora = (target?.flora ?? "SOME") + " " + cinnamon_bun_flora_generic_plurals.randomElement()!
        let fauna = (target?.fauna ?? "SOME") + " " + cinnamon_bun_fauna_generic_plurals.randomElement()!
        let atmo = (target?.atmosphere ?? "SOME") + " " + cinnamon_bun_atmo_generic_plurals.randomElement()!
        let planet = target?.description ?? "SOME BODY"
        activity = activity.replacingOccurrences(of: "{flora}", with: flora)
        activity = activity.replacingOccurrences(of: "{fauna}", with: fauna)
        activity = activity.replacingOccurrences(of: "{atmo}", with: atmo)
        activity = activity.replacingOccurrences(of: "{planet}", with: planet)
        return activity
    }
}

// MARK: - Rendering (VisibleUniverse.kt, assets from Assets.kt)

let DRAW_ORBITS = true
let DRAW_GRAVITATIONAL_FIELDS = true
let DRAW_STAR_GRAVITATIONAL_FIELDS = true

let DEFAULT_CAMERA_ZOOM: Float = 1
let MIN_CAMERA_ZOOM: Float = 250 / UNIVERSE_RANGE
let MAX_CAMERA_ZOOM: Float = 5

let spaceshipSvg = """
M11.853 0
C11.853 -4.418 8.374 -8 4.083 -8
L-5.5 -8
C-6.328 -8 -7 -7.328 -7 -6.5
C-7 -5.672 -6.328 -5 -5.5 -5
L-2.917 -5
C-1.26 -5 0.083 -3.657 0.083 -2
L0.083 2
C0.083 3.657 -1.26 5 -2.917 5
L-5.5 5
C-6.328 5 -7 5.672 -7 6.5
C-7 7.328 -6.328 8 -5.5 8
L4.083 8
C8.374 8 11.853 4.418 11.853 0
Z
"""

func parseSvgPath(_ d: String) -> CGPath {
    let path = CGMutablePath()
    var lastx: Float = 0, lasty: Float = 0
    let regex = try! NSRegularExpression(pattern: "([A-Za-z])\\s*([-.,0-9e ]+)")
    let ns = d as NSString
    regex.enumerateMatches(in: d, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
        guard let m = m else { return }
        let cmd = ns.substring(with: m.range(at: 1))
        let argsStr = ns.substring(with: m.range(at: 2))
        let args = argsStr.split(whereSeparator: { $0 == " " || $0 == "\n" }).compactMap { Float($0) }
        switch cmd {
        case "M":
            path.move(to: CGPoint(x: CGFloat(args[0]), y: CGFloat(args[1])))
            lastx = args[0]; lasty = args[1]
        case "C":
            let c1 = CGPoint(x: CGFloat(args[0]), y: CGFloat(args[1]))
            let c2 = CGPoint(x: CGFloat(args[2]), y: CGFloat(args[3]))
            let cpt = CGPoint(x: CGFloat(args[4]), y: CGFloat(args[5]))
            path.addCurve(to: cpt, control1: c1, control2: c2)
            lastx = args[4]; lasty = args[5]
        case "L":
            path.addLine(to: CGPoint(x: CGFloat(args[0]), y: CGFloat(args[1])))
            lastx = args[0]; lasty = args[1]
        case "l":
            path.addLine(to: CGPoint(x: CGFloat(lastx + args[0]), y: CGFloat(lasty + args[1])))
            lastx += args[0]; lasty += args[1]
        case "Z":
            path.closeSubpath()
        default:
            break
        }
    }
    return path
}

let spaceshipPath = parseSvgPath(spaceshipSvg)

func createPolygonPath(_ radius: Float, _ sides: Int) -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: CGFloat(radius), y: 0))
    let step = PI2f / Float(sides)
    for i in 1..<sides {
        p.addLine(to: CGPoint(x: CGFloat(radius * cos(step * Float(i))),
                              y: CGFloat(radius * sin(step * Float(i)))))
    }
    p.closeSubpath()
    return p
}

func createStarPath(_ radius1: Float, _ radius2: Float, _ points: Int) -> CGPath {
    let p = CGMutablePath()
    let step = PI2f / Float(points)
    p.move(to: CGPoint(x: CGFloat(radius1), y: 0))
    p.addLine(to: CGPoint(x: CGFloat(radius2 * cos(step * 0.5)), y: CGFloat(radius2 * sin(step * 0.5))))
    for i in 1..<points {
        p.addLine(to: CGPoint(x: CGFloat(radius1 * cos(step * Float(i))), y: CGFloat(radius1 * sin(step * Float(i)))))
        p.addLine(to: CGPoint(x: CGFloat(radius2 * cos(step * (Float(i) + 0.5))), y: CGFloat(radius2 * sin(step * (Float(i) + 0.5)))))
    }
    p.closeSubpath()
    return p
}

// thrust marker (thrustPath = createPolygon(-3, 3) translated by (-5, 0))
var thrustPath: CGPath = {
    let p = CGMutablePath()
    // polygon with radius -3, 3 sides: moveTo(-3,0), lineTo(-3*cos(2pi/3)...) — replicate original
    let radius: Float = -3
    let sides = 3
    let step = PI2f / Float(sides)
    p.move(to: CGPoint(x: CGFloat(radius), y: 0))
    for i in 1..<sides {
        p.addLine(to: CGPoint(x: CGFloat(radius * cos(step * Float(i))), y: CGFloat(radius * sin(step * Float(i)))))
    }
    p.closeSubpath()
    var tr = CGAffineTransform(translationX: -5, y: 0)
    return p.copy(using: &tr)!
}()

// MARK: - The ScreenSaverView


// Seeded RNG compatible-enough with kotlin.random.Random usage
extension SeededGenerator {
    mutating func nextFloat() -> Float {
        Float(UInt32(truncatingIfNeeded: next())) / Float(UInt32.max)
    }
    mutating func nextFloat(in range: ClosedRange<Float>) -> Float {
        range.lowerBound + (range.upperBound - range.lowerBound) * nextFloat()
    }
    mutating func next(_ range: ClosedRange<Int>) -> Int {
        range.lowerBound + Int(next() % UInt64(range.count))
    }
    mutating func next(_ range: Range<Int>) -> Int {
        range.lowerBound + Int(next() % UInt64(range.count))
    }
}

struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) {
        state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }
    mutating func next() -> UInt64 {
        // xorshift64*
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        return state &* 0x2545F4914F6CDD1D
    }
}
