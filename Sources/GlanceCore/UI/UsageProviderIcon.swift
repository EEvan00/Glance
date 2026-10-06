import SwiftUI

struct UsageProviderIcon: View {
    enum Provider { case codex, claude }
    let provider: Provider

    var body: some View {
        Group {
            switch provider {
            case .codex:
                CodexOfficialMark().fill(.white, style: FillStyle(eoFill: true))
            case .claude:
                ClaudeCodePixels().fill(.white, style: FillStyle(eoFill: true, antialiased: false))
                    .frame(height: 16)
            }
        }.frame(width: 18, height: 18).accessibilityHidden(true)
    }
}

/// Exact paths from the official Codex app asset codex_new-f14177b03534.svg.
/// The unchanged source SVG is retained in Support/ProviderIcons/Codex.svg.
private struct CodexOfficialMark: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 16.0005, y: 13.5992))
        p.addCurve(to: CGPoint(x: 16.9009, y: 14.4996), control1: CGPoint(x: 16.4972, y: 13.5995), control2: CGPoint(x: 16.9007, y: 14.0029))
        p.addCurve(to: CGPoint(x: 16.0005, y: 15.4), control1: CGPoint(x: 16.9009, y: 14.9965), control2: CGPoint(x: 16.4974, y: 15.3997))
        p.addLine(to: CGPoint(x: 13.0005, y: 15.4))
        p.addCurve(to: CGPoint(x: 12.1002, y: 14.4996), control1: CGPoint(x: 12.5035, y: 15.4), control2: CGPoint(x: 12.1002, y: 14.9967))
        p.addCurve(to: CGPoint(x: 13.0005, y: 13.5992), control1: CGPoint(x: 12.1004, y: 14.0027), control2: CGPoint(x: 12.5036, y: 13.5992))
        p.addLine(to: CGPoint(x: 16.0005, y: 13.5992))
        p.closeSubpath()
        p.move(to: CGPoint(x: 8.03765, y: 8.72811))
        p.addCurve(to: CGPoint(x: 9.27203, y: 9.03671), control1: CGPoint(x: 8.46377, y: 8.47284), control2: CGPoint(x: 9.01638, y: 8.61074))
        p.addLine(to: CGPoint(x: 10.6177, y: 11.2789))
        p.addCurve(to: CGPoint(x: 10.6177, y: 12.7203), control1: CGPoint(x: 10.8836, y: 11.7221), control2: CGPoint(x: 10.8834, y: 12.277))
        p.addLine(to: CGPoint(x: 9.27203, y: 14.9625))
        p.addCurve(to: CGPoint(x: 8.03765, y: 15.2711), control1: CGPoint(x: 9.01633, y: 15.3887), control2: CGPoint(x: 8.46385, y: 15.5267))
        p.addCurve(to: CGPoint(x: 7.72906, y: 14.0367), control1: CGPoint(x: 7.61143, y: 15.0153), control2: CGPoint(x: 7.47333, y: 14.4629))
        p.addLine(to: CGPoint(x: 8.95074, y: 11.9996))
        p.addLine(to: CGPoint(x: 7.72906, y: 9.96249))
        p.addCurve(to: CGPoint(x: 8.03765, y: 8.72811), control1: CGPoint(x: 7.47341, y: 9.53628), control2: CGPoint(x: 7.61146, y: 8.98382))
        p.closeSubpath()
        p.move(to: CGPoint(x: 9.3316, y: 2.03768))
        p.addCurve(to: CGPoint(x: 14.356, y: 3.20174), control1: CGPoint(x: 11.1644, y: 1.54688), control2: CGPoint(x: 13.0268, y: 2.04668))
        p.addCurve(to: CGPoint(x: 19.2935, y: 4.70663), control1: CGPoint(x: 16.0859, y: 2.86512), control2: CGPoint(x: 17.9511, y: 3.36418))
        p.addCurve(to: CGPoint(x: 20.7964, y: 9.64217), control1: CGPoint(x: 20.6356, y: 6.04882), control2: CGPoint(x: 21.1326, y: 7.91288))
        p.addCurve(to: CGPoint(x: 21.9625, y: 14.6685), control1: CGPoint(x: 21.9527, y: 10.9716), control2: CGPoint(x: 22.4534, y: 12.8349))
        p.addCurve(to: CGPoint(x: 18.439, y: 18.439), control1: CGPoint(x: 21.4711, y: 16.5025), control2: CGPoint(x: 20.1051, y: 17.8657))
        p.addCurve(to: CGPoint(x: 14.6695, y: 21.9615), control1: CGPoint(x: 17.8658, y: 20.1047), control2: CGPoint(x: 16.503, y: 21.47))
        p.addCurve(to: CGPoint(x: 9.64312, y: 20.7955), control1: CGPoint(x: 12.8356, y: 22.4528), control2: CGPoint(x: 10.9727, y: 21.9519))
        p.addCurve(to: CGPoint(x: 4.70757, y: 19.2926), control1: CGPoint(x: 7.91371, y: 21.1319), control2: CGPoint(x: 6.04993, y: 20.635))
        p.addCurve(to: CGPoint(x: 3.20269, y: 14.357), control1: CGPoint(x: 3.36558, y: 17.9505), control2: CGPoint(x: 2.86659, y: 16.0866))
        p.addCurve(to: CGPoint(x: 2.03863, y: 9.33065), control1: CGPoint(x: 2.04693, y: 13.0273), control2: CGPoint(x: 1.54757, y: 11.1638))
        p.addCurve(to: CGPoint(x: 5.56011, y: 5.55917), control1: CGPoint(x: 2.52997, y: 7.49759), control2: CGPoint(x: 3.89436, y: 6.13282))
        p.addCurve(to: CGPoint(x: 9.3316, y: 2.03768), control1: CGPoint(x: 6.13382, y: 3.8935), control2: CGPoint(x: 7.49837, y: 2.52891))
        p.closeSubpath()
        p.move(to: CGPoint(x: 13.2623, y: 4.63534))
        p.addCurve(to: CGPoint(x: 9.79742, y: 3.77596), control1: CGPoint(x: 12.3606, y: 3.80149), control2: CGPoint(x: 11.067, y: 3.4361))
        p.addCurve(to: CGPoint(x: 7.22515, y: 6.25253), control1: CGPoint(x: 8.52745, y: 4.11626), control2: CGPoint(x: 7.58924, y: 5.0796))
        p.addCurve(to: CGPoint(x: 6.25445, y: 7.22323), control1: CGPoint(x: 7.08145, y: 6.71575), control2: CGPoint(x: 6.71753, y: 7.07928))
        p.addCurve(to: CGPoint(x: 3.77789, y: 9.79647), control1: CGPoint(x: 5.08133, y: 7.58702), control2: CGPoint(x: 4.11844, y: 8.52622))
        p.addCurve(to: CGPoint(x: 4.63531, y: 13.2623), control1: CGPoint(x: 3.43759, y: 11.0667), control2: CGPoint(x: 3.80148, y: 12.3606))
        p.addCurve(to: CGPoint(x: 4.99078, y: 14.5885), control1: CGPoint(x: 4.96467, y: 13.6184), control2: CGPoint(x: 5.09776, y: 14.1154))
        p.addCurve(to: CGPoint(x: 5.98101, y: 18.0191), control1: CGPoint(x: 4.71939, y: 15.7864), control2: CGPoint(x: 5.05109, y: 17.0891))
        p.addCurve(to: CGPoint(x: 9.41168, y: 19.0084), control1: CGPoint(x: 6.91085, y: 18.949), control2: CGPoint(x: 8.21345, y: 19.2801))
        p.addLine(to: CGPoint(x: 9.58941, y: 18.9791))
        p.addCurve(to: CGPoint(x: 10.5982, y: 19.2496), control1: CGPoint(x: 9.94695, y: 18.9432), control2: CGPoint(x: 10.3065, y: 19.0397))
        p.addLine(to: CGPoint(x: 10.7378, y: 19.3639))
        p.addLine(to: CGPoint(x: 10.9117, y: 19.5142))
        p.addCurve(to: CGPoint(x: 14.2037, y: 20.2223), control1: CGPoint(x: 11.8015, y: 20.2407), control2: CGPoint(x: 13.0127, y: 20.5413))
        p.addCurve(to: CGPoint(x: 16.775, y: 17.7457), control1: CGPoint(x: 15.4733, y: 19.8818), control2: CGPoint(x: 16.4111, y: 18.9191))
        p.addCurve(to: CGPoint(x: 17.7466, y: 16.775), control1: CGPoint(x: 16.9189, y: 17.2824), control2: CGPoint(x: 17.2832, y: 16.9186))
        p.addLine(to: CGPoint(x: 17.9634, y: 16.6998))
        p.addCurve(to: CGPoint(x: 20.2242, y: 14.2027), control1: CGPoint(x: 19.0376, y: 16.2923), control2: CGPoint(x: 19.9051, y: 15.3936))
        p.addCurve(to: CGPoint(x: 19.3648, y: 10.7369), control1: CGPoint(x: 20.5641, y: 12.9328), control2: CGPoint(x: 20.1989, y: 11.6385))
        p.addCurve(to: CGPoint(x: 19.0093, y: 9.41073), control1: CGPoint(x: 19.0353, y: 10.3806), control2: CGPoint(x: 18.9021, y: 9.88399))
        p.addLine(to: CGPoint(x: 19.0533, y: 9.18514))
        p.addCurve(to: CGPoint(x: 18.0201, y: 5.98006), control1: CGPoint(x: 19.2372, y: 8.0514), control2: CGPoint(x: 18.8917, y: 6.85176))
        p.addCurve(to: CGPoint(x: 14.5884, y: 4.98983), control1: CGPoint(x: 17.0901, y: 5.05003), control2: CGPoint(x: 15.7865, y: 4.71826))
        p.addCurve(to: CGPoint(x: 13.2623, y: 4.63534), control1: CGPoint(x: 14.1153, y: 5.09712), control2: CGPoint(x: 13.6186, y: 4.96467))
        p.closeSubpath()
        return p.applying(CGAffineTransform(scaleX: rect.width / 24, y: rect.height / 24))
    }
}

/// Pixel geometry keeps the Claude Code mascot crisp at menu-icon sizes.
private struct ClaudeCodePixels: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addRect(CGRect(x: 2, y: 1, width: 12, height: 9))
        p.addRect(CGRect(x: 0, y: 3, width: 2, height: 5))
        p.addRect(CGRect(x: 14, y: 3, width: 2, height: 5))
        for x in [3, 5, 10, 12] { p.addRect(CGRect(x: x, y: 10, width: 1, height: 3)) }
        p.addRect(CGRect(x: 5, y: 3, width: 1, height: 3))
        p.addRect(CGRect(x: 10, y: 3, width: 1, height: 3))
        return p.applying(CGAffineTransform(scaleX: rect.width / 16, y: rect.height / 14))
    }
}
