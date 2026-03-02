import SwiftUI

/// Unified color system: gold-on-dark with semantic status colors.
/// Maps to ANSI codes in ui/tokens/stampede-colors.sh for terminal parity.
struct StampedeColors {
    // Brand
    static let gold       = Color(red: 245/255, green: 166/255, blue: 35/255)
    static let goldBright = Color(red: 255/255, green: 215/255, blue: 0/255)
    static let goldDim    = Color(red: 139/255, green: 117/255, blue: 53/255)

    // Backgrounds (depth layers)
    static let bgDeep     = Color(red: 13/255, green: 17/255, blue: 23/255)
    static let bgSurface  = Color(red: 22/255, green: 27/255, blue: 34/255)
    static let bgElevated = Color(red: 28/255, green: 35/255, blue: 51/255)
    static let bgHover    = Color(red: 33/255, green: 38/255, blue: 45/255)

    // Status
    static let green  = Color(red: 74/255, green: 222/255, blue: 128/255)
    static let blue   = Color(red: 56/255, green: 189/255, blue: 248/255)
    static let red    = Color(red: 248/255, green: 113/255, blue: 113/255)
    static let purple = Color(red: 192/255, green: 132/255, blue: 252/255)
    static let orange = Color(red: 251/255, green: 146/255, blue: 60/255)
    static let gray   = Color(red: 100/255, green: 116/255, blue: 139/255)

    // Text
    static let textPrimary   = Color(red: 232/255, green: 232/255, blue: 237/255)
    static let textSecondary = Color(red: 152/255, green: 152/255, blue: 166/255)
    static let textTertiary  = Color(red: 92/255, green: 92/255, blue: 110/255)

    // Border
    static let border = Color(red: 48/255, green: 54/255, blue: 61/255)
}

extension View {
    func stampedeCard() -> some View {
        self.background(StampedeColors.bgSurface)
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(StampedeColors.border, lineWidth: 1))
    }

    func goldGlow() -> some View {
        self.shadow(color: StampedeColors.gold.opacity(0.15), radius: 10)
    }
}
