import AppKit
import CoreGraphics
import CoreText

enum StatusIconRenderer {
    // Keep the 7pt rounded Wi-Fi strokes fully inside the bitmap.
    private static let wifiCanvasBounds = CGRect(
        x: 31.5,
        y: 34.4,
        width: 56,
        height: 56
    )

    static func image(
        snapshot: StatusSnapshot,
        size: CGFloat,
        options: BatteryIconOptions = .standard,
        connectionOptions: ConnectionIconOptions = .standard
    ) -> NSImage {
        image(
            menuBarStatus: MenuBarStatus(snapshot: snapshot),
            size: size,
            options: options,
            connectionOptions: connectionOptions
        )
    }

    static func image(
        menuBarStatus: MenuBarStatus,
        size: CGFloat,
        countdown: CountdownIndicator? = nil,
        options: BatteryIconOptions = .standard,
        connectionOptions: ConnectionIconOptions = .standard
    ) -> NSImage {
        // Resolve colors while AppKit draws into each menu bar. A pre-rendered
        // bitmap would keep the first display's light or dark foreground.
        NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            let foreground = NSColor.labelColor.usingColorSpace(.deviceRGB)?.cgColor
                ?? CGColor(gray: 1, alpha: 1)
            let criticalColor = NSColor.systemRed.usingColorSpace(.deviceRGB)?.cgColor
                ?? Self.defaultCriticalColor

            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            draw(
                menuBarStatus: menuBarStatus,
                countdown: countdown,
                options: options,
                connectionOptions: connectionOptions,
                in: context,
                size: size,
                foreground: foreground,
                criticalColor: criticalColor
            )
            return true
        }
    }

    static func wifiImage(wifi: WiFiStatus, size: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        defer { image.unlockFocus() }

        guard let context = NSGraphicsContext.current?.cgContext else { return image }

        context.saveGState()
        defer { context.restoreGState() }

        let scale = size / wifiCanvasBounds.width
        context.translateBy(x: 0, y: size)
        context.scaleBy(x: scale, y: -scale)
        context.translateBy(x: -wifiCanvasBounds.minX, y: -wifiCanvasBounds.minY)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        drawWiFi(
            wifi,
            options: .standard,
            in: context,
            foreground: CGColor(gray: 1, alpha: 1)
        )
        image.isTemplate = true
        return image
    }

    static func render(
        snapshot: StatusSnapshot,
        size: CGFloat,
        scale: CGFloat,
        foreground: CGColor,
        options: BatteryIconOptions = .standard,
        connectionOptions: ConnectionIconOptions = .standard
    ) -> CGImage? {
        render(
            menuBarStatus: MenuBarStatus(snapshot: snapshot),
            size: size,
            scale: scale,
            foreground: foreground,
            options: options,
            connectionOptions: connectionOptions
        )
    }

    static func render(
        menuBarStatus: MenuBarStatus,
        size: CGFloat,
        countdown: CountdownIndicator? = nil,
        scale: CGFloat,
        foreground: CGColor,
        options: BatteryIconOptions = .standard,
        connectionOptions: ConnectionIconOptions = .standard
    ) -> CGImage? {
        guard size.isFinite, scale.isFinite, size > 0, scale > 0 else { return nil }

        let pixelLength = (size * scale).rounded(.up)
        guard pixelLength.isFinite,
              let pixelDimension = Int(exactly: pixelLength),
              pixelDimension > 0,
              pixelDimension <= Int.max / 4
        else {
            return nil
        }

        guard let context = CGContext(
            data: nil,
            width: pixelDimension,
            height: pixelDimension,
            bitsPerComponent: 8,
            bytesPerRow: pixelDimension * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.scaleBy(x: scale, y: scale)
        draw(
            menuBarStatus: menuBarStatus,
            countdown: countdown,
            options: options,
            connectionOptions: connectionOptions,
            in: context,
            size: size,
            foreground: foreground,
            criticalColor: defaultCriticalColor
        )
        return context.makeImage()
    }

    private static func draw(
        menuBarStatus: MenuBarStatus,
        countdown: CountdownIndicator?,
        options: BatteryIconOptions,
        connectionOptions: ConnectionIconOptions,
        in context: CGContext,
        size: CGFloat,
        foreground: CGColor,
        criticalColor: CGColor
    ) {
        context.saveGState()
        defer { context.restoreGState() }

        let scale = size / StatusIconGeometry.canvas.width
        context.translateBy(x: 0, y: size)
        context.scaleBy(x: scale, y: -scale)

        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setAlpha(countdown?.isDimmed == true ? 0.05 : 1)

        if let countdown {
            drawCountdown(countdown, options: options, in: context, foreground: foreground)
        } else {
            drawBattery(
                menuBarStatus.battery,
                options: options,
                in: context,
                foreground: foreground,
                criticalColor: criticalColor
            )
        }
        if menuBarStatus.connection == .ethernet {
            if connectionOptions.showsWiFiIconForEthernet {
                drawStandardWiFi(menuBarStatus.wifi, in: context, foreground: foreground)
            } else {
                drawEthernet(in: context, foreground: foreground)
            }
        } else {
            drawWiFi(
                menuBarStatus.wifi,
                options: connectionOptions,
                in: context,
                foreground: foreground
            )
        }
        drawVolume(menuBarStatus.volume, in: context, foreground: foreground)
    }

    private static func drawCountdown(_ countdown: CountdownIndicator, options: BatteryIconOptions,
                                      in context: CGContext, foreground: CGColor) {
        context.saveGState()
        defer { context.restoreGState() }
        context.setLineWidth(8)
        context.setStrokeColor(foreground.copy(alpha: 0.22) ?? foreground)
        context.addPath(StatusIconGeometry.batteryTrack(hasTopGap: true, topGapWidth: StatusIconGeometry.batteryValueTopGapWidth))
        context.strokePath()
        context.setStrokeColor(foreground)
        context.addPath(StatusIconGeometry.batteryFill(progress: countdown.progress, hasTopGap: true,
                                                      topGapWidth: StatusIconGeometry.batteryValueTopGapWidth))
        context.strokePath()
        // Keep long custom durations inside the existing number slot.
        let digits = String(countdown.number).count
        let fontSize = batteryValueFontSize(scale: options.textScale) * min(1, 3.0 / Double(digits))
        drawBatteryPercentage(countdown.number, color: foreground, fontSize: fontSize, in: context)
    }

    private static func drawBattery(
        _ battery: BatteryStatus,
        options: BatteryIconOptions,
        in context: CGContext,
        foreground: CGColor,
        criticalColor: CGColor
    ) {
        let indicator = options.showsChargingIndicator ? battery.indicatorSymbol : nil
        let showsChargingIndicator = indicator != nil
        let hasTopGap = showsChargingIndicator || options.showsPercentage
        let topGapWidth = showsChargingIndicator
            ? StatusIconGeometry.batteryChargingBoltTopGapWidth
            : StatusIconGeometry.batteryValueTopGapWidth

        context.setLineWidth(8)
        context.setStrokeColor(foreground.copy(alpha: 0.22) ?? foreground)
        context.addPath(StatusIconGeometry.batteryTrack(
            hasTopGap: hasTopGap,
            topGapWidth: topGapWidth
        ))
        context.strokePath()

        let role = options.usesStatusColors
            ? StatusMappings.batteryColorRole(
                battery,
                criticalThreshold: options.criticalThreshold
            )
            : .foreground
        let arcColor = color(
            for: role,
            foreground: foreground,
            criticalColor: criticalColor
        )

        context.setStrokeColor(arcColor)
        context.addPath(StatusIconGeometry.batteryFill(
            progress: StatusMappings.batteryProgress(battery),
            hasTopGap: hasTopGap,
            topGapWidth: topGapWidth
        ))
        context.strokePath()

        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: 0.75),
            blur: 0.75,
            color: CGColor(gray: 0, alpha: 0.38)
        )
        defer { context.restoreGState() }

        if indicator == "powerplug.portrait.fill" {
            drawPowerPlug(textScale: options.textScale, color: foreground, in: context)
        } else if showsChargingIndicator {
            context.setFillColor(foreground)
            let bolt = StatusIconGeometry.batteryChargingBolt()
            let source = bolt.boundingBoxOfPath
            let target = batteryIndicatorRect(aspectRatio: source.width / source.height,
                                              textScale: options.textScale)
            let scale = target.height / source.height
            var transform = CGAffineTransform(a: scale, b: 0, c: 0, d: scale,
                                              tx: target.minX - source.minX * scale,
                                              ty: target.minY - source.minY * scale)
            context.addPath(bolt.copy(using: &transform) ?? bolt)
            context.fillPath()
        } else if options.showsPercentage {
            drawBatteryPercentage(
                battery.percentage,
                color: foreground,
                fontSize: batteryValueFontSize(scale: options.textScale),
                in: context
            )
        }
    }

    private static func color(
        for role: BatteryColorRole,
        foreground: CGColor,
        criticalColor: CGColor
    ) -> CGColor {
        switch role {
        case .foreground:
            foreground
        case .critical:
            criticalColor
        case .charging:
            if usesDarkStatusPalette(foreground: foreground) {
                CGColor(red: 31.0 / 255.0, green: 143.0 / 255.0, blue: 61.0 / 255.0, alpha: 1)
            } else {
                CGColor(red: 52.0 / 255.0, green: 199.0 / 255.0, blue: 89.0 / 255.0, alpha: 1)
            }
        case .lowPower:
            if usesDarkStatusPalette(foreground: foreground) {
                CGColor(red: 201.0 / 255.0, green: 151.0 / 255.0, blue: 0, alpha: 1)
            } else {
                CGColor(red: 242.0 / 255.0, green: 185.0 / 255.0, blue: 0, alpha: 1)
            }
        }
    }

    private static func usesDarkStatusPalette(foreground: CGColor) -> Bool {
        guard let color = NSColor(cgColor: foreground)?.usingColorSpace(.deviceRGB) else {
            return false
        }
        return color.brightnessComponent < 0.5
    }

    private static func drawBatteryPercentage(
        _ percentage: Int,
        color: CGColor,
        fontSize: CGFloat,
        in context: CGContext
    ) {
        let font = batteryValueFont(size: fontSize)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .kern: -fontSize * 0.04,
            .foregroundColor: NSColor(cgColor: color) ?? .white
        ]
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: String(percentage), attributes: attributes)
        )
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        let baseline = StatusIconGeometry.batteryValueBaseline(fontSize: fontSize)

        context.setFillColor(color)
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.textPosition = CGPoint(x: baseline.x - width / 2, y: baseline.y)
        CTLineDraw(line, context)
    }

    // Normalize to visible pixels: SF Symbols includes side bearings and vertical
    // padding that otherwise make the plug look smaller and lower than the bolt.
    private static let powerPlugMask: CGImage? = {
        guard let symbol = NSImage(systemSymbolName: "powerplug.portrait.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 180, weight: .regular)),
              let image = symbol.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let bitmap = NSBitmapImageRep(cgImage: image)
        var minX = bitmap.pixelsWide, minY = bitmap.pixelsHigh, maxX = -1, maxY = -1
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.01 {
                minX = min(minX, x); minY = min(minY, y)
                maxX = max(maxX, x); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return image.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))
    }()

    static func batteryIndicatorRect(aspectRatio: CGFloat, textScale: Double) -> CGRect {
        // Start above the ring crest, like the percentage, but leave the Wi-Fi
        // arcs clear even at the largest symbol setting. Both symbols share this anchor.
        let height = min(36, 21 * CGFloat(textScale))
        let width = height * aspectRatio
        return CGRect(x: 59.5 - width / 2, y: 0, width: width, height: height)
    }

    private static func drawPowerPlug(textScale: Double, color: CGColor, in context: CGContext) {
        guard let image = powerPlugMask else { return }
        let target = batteryIndicatorRect(aspectRatio: CGFloat(image.width) / CGFloat(image.height),
                                          textScale: textScale)
        context.saveGState()
        defer { context.restoreGState() }
        context.translateBy(x: target.minX, y: target.maxY)
        context.scaleBy(x: 1, y: -1)
        let bounds = CGRect(origin: .zero, size: target.size)
        context.clip(to: bounds, mask: image)
        context.setFillColor(color)
        context.fill(bounds)
    }

    private static func batteryValueFontSize(scale: Double) -> CGFloat {
        StatusIconGeometry.batteryValueBaseFontSize * CGFloat(scale)
    }

    private static var defaultCriticalColor: CGColor {
        CGColor(red: 255.0 / 255.0, green: 59.0 / 255.0, blue: 48.0 / 255.0, alpha: 1)
    }

    private static func batteryValueFont(size: CGFloat) -> NSFont {
        let fallback = NSFont.systemFont(ofSize: size, weight: .bold)
        guard let descriptor = fallback.fontDescriptor.withDesign(.rounded) else {
            return fallback
        }
        return NSFont(descriptor: descriptor, size: size) ?? fallback
    }

    private static func drawEthernet(
        in context: CGContext,
        foreground: CGColor
    ) {
        context.setStrokeColor(foreground)
        context.setLineWidth(StatusIconGeometry.ethernetStrokeWidth)
        for path in StatusIconGeometry.ethernetChevrons() {
            context.addPath(path)
            context.strokePath()
        }

        context.setFillColor(foreground)
        let radius = StatusIconGeometry.ethernetDotRadius
        for point in StatusIconGeometry.ethernetDots() {
            context.fillEllipse(
                in: CGRect(
                    x: point.x - radius,
                    y: point.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )
            )
        }
    }

    private static func drawWiFi(
        _ wifi: WiFiStatus,
        options: ConnectionIconOptions,
        in context: CGContext,
        foreground: CGColor
    ) {
        let mutedColor = foreground.copy(alpha: 0.30) ?? foreground

        context.setLineWidth(7)

        switch wifi.state {
        case .connected:
            drawStandardWiFi(wifi, in: context, foreground: foreground)
        case .notAssociated, .off, .unavailable:
            drawWiFiSignal(level: 3, color: mutedColor, in: context)

            if wifi.state == .off || wifi.state == .unavailable {
                context.setStrokeColor(mutedColor)
                context.setLineWidth(6)
                context.addPath(StatusIconGeometry.wifiOffSlash())
                context.strokePath()
            }
        case .noInternet:
            drawWiFiSignal(level: 3, color: mutedColor, includeDot: false, in: context)

            let overlay = StatusIconGeometry.noInternetOverlay()
            context.setStrokeColor(mutedColor)
            context.setLineWidth(5)
            context.addPath(overlay.stem)
            context.strokePath()

            context.setFillColor(mutedColor)
            context.addPath(overlay.dot)
            context.fillPath()
        case .hotspot where options.showsWiFiIconForHotspot:
            drawStandardWiFi(wifi, in: context, foreground: foreground)
        case .hotspot:
            context.setStrokeColor(foreground)
            context.setLineWidth(5)
            for path in StatusIconGeometry.hotspotOverlay() {
                context.addPath(path)
                context.strokePath()
            }
        case .temporary where options.showsWiFiIconForTemporaryConnection:
            drawStandardWiFi(wifi, in: context, foreground: foreground)
        case .temporary:
            context.setFillColor(foreground)
            context.setStrokeColor(foreground)
            context.setLineWidth(7)
            context.addPath(StatusIconGeometry.temporaryWedge())
            context.drawPath(using: .fillStroke)

            context.saveGState()
            context.setBlendMode(.clear)
            context.setLineWidth(2.5)
            context.addPath(StatusIconGeometry.temporaryScreenOutline())
            context.strokePath()
            context.addPath(StatusIconGeometry.temporaryScreenStand())
            context.fillPath()
            context.restoreGState()
        case .shared where options.showsWiFiIconForInternetSharing:
            drawStandardWiFi(wifi, in: context, foreground: foreground)
        case .shared:
            context.setFillColor(foreground)
            context.setStrokeColor(foreground)
            context.setLineWidth(7)
            context.addPath(StatusIconGeometry.sharedWedge())
            context.drawPath(using: .fillStroke)

            context.saveGState()
            context.setBlendMode(.clear)
            context.addPath(StatusIconGeometry.sharedArrowCutout())
            context.fillPath()
            context.restoreGState()
        }
    }

    private static func drawStandardWiFi(
        _ wifi: WiFiStatus,
        in context: CGContext,
        foreground: CGColor
    ) {
        context.setLineWidth(7)
        let bars = StatusMappings.wifiBars(rssi: wifi.rssi)
        if bars == 0 {
            let mutedColor = foreground.copy(alpha: 0.30) ?? foreground
            drawWiFiSignal(level: 3, color: mutedColor, in: context)
        } else {
            drawWiFiSignal(level: bars, color: foreground, in: context)
        }
    }

    private static func drawWiFiSignal(
        level: Int,
        color: CGColor,
        includeDot: Bool = true,
        in context: CGContext
    ) {
        context.setStrokeColor(color)
        for path in StatusIconGeometry.wifiArcs(level: level) {
            context.addPath(path)
            context.strokePath()
        }

        guard includeDot else { return }
        context.setFillColor(color)
        context.addPath(StatusIconGeometry.wifiDot())
        context.fillPath()
    }

    private static func drawVolume(
        _ volume: MenuBarVolumeStatus,
        in context: CGContext,
        foreground: CGColor
    ) {
        let level = StatusMappings.volumeSteps(scalar: volume.scalar, isMuted: volume.isMuted) ?? 0
        let hiddenColor = foreground.copy(alpha: 0.22) ?? foreground

        for (index, point) in StatusIconGeometry.volumeDots().enumerated() {
            context.setFillColor(index < level ? foreground : hiddenColor)
            let radius = StatusIconGeometry.volumeDotRadius
            context.fillEllipse(
                in: CGRect(
                    x: point.x - radius,
                    y: point.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )
            )
        }
    }
}
