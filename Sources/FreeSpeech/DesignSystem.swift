import AppKit
import SwiftUI

// Port of the ETok "Greenlight" design system (DESIGN.md), red variant:
// same ink neutrals, hairlines, radii, and mono label voice, with the volt-lime
// accent swapped for Apple's dark-mode system red so it reads native on macOS.
enum DS {
    static let ink0 = NSColor(srgbRed: 0.039, green: 0.039, blue: 0.047, alpha: 1)   // 0A0A0C
    static let ink1 = NSColor(srgbRed: 0.075, green: 0.075, blue: 0.094, alpha: 1)   // 131318
    static let ink2 = NSColor(srgbRed: 0.114, green: 0.114, blue: 0.141, alpha: 1)   // 1D1D24
    static let ink3 = NSColor(srgbRed: 0.149, green: 0.149, blue: 0.184, alpha: 1)   // 26262F
    static let line = NSColor(srgbRed: 0.165, green: 0.165, blue: 0.200, alpha: 1)   // 2A2A33
    static let paper = NSColor(srgbRed: 0.961, green: 0.961, blue: 0.941, alpha: 1)  // F5F5F0
    static let muted = NSColor(srgbRed: 0.557, green: 0.557, blue: 0.600, alpha: 1)  // 8E8E99
    static let faint = NSColor(srgbRed: 0.333, green: 0.333, blue: 0.373, alpha: 1)  // 55555F
    static let accent = NSColor(srgbRed: 1.0, green: 0.271, blue: 0.227, alpha: 1)   // FF453A
    static let accentDim = NSColor(srgbRed: 0.792, green: 0.227, blue: 0.196, alpha: 1) // CA3A32
    static let glass = NSColor(srgbRed: 0.075, green: 0.075, blue: 0.094, alpha: 0.88)

    static let radiusControl: CGFloat = 14
    static let radiusCard: CGFloat = 20
    static let radiusSheet: CGFloat = 28

    // Greenlight's mono label voice: micro size, uppercase, wide tracking.
    static func microLabel(_ text: String) -> NSAttributedString {
        NSAttributedString(
            string: text.uppercased(),
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
                .kern: 1.2,
                .foregroundColor: muted,
            ])
    }
}

// Greenlight ghost button: transparent fill, hairline border, paper text.
struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.dsPaper)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(
                configuration.isPressed ? Color.dsInk3 : Color.clear,
                in: RoundedRectangle(cornerRadius: DS.radiusControl, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.radiusControl, style: .continuous)
                    .strokeBorder(Color.dsLine, lineWidth: 1))
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

extension Color {
    static let dsInk0 = Color(nsColor: DS.ink0)
    static let dsInk1 = Color(nsColor: DS.ink1)
    static let dsInk2 = Color(nsColor: DS.ink2)
    static let dsInk3 = Color(nsColor: DS.ink3)
    static let dsLine = Color(nsColor: DS.line)
    static let dsPaper = Color(nsColor: DS.paper)
    static let dsMuted = Color(nsColor: DS.muted)
    static let dsFaint = Color(nsColor: DS.faint)
    static let dsAccent = Color(nsColor: DS.accent)
    static let dsAccentDim = Color(nsColor: DS.accentDim)
}
