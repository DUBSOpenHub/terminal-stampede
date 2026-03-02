import SwiftUI

struct StampedeColors {
    static let gold       = Color(red: 245/255, green: 166/255, blue: 35/255)
    static let goldBright = Color(red: 255/255, green: 215/255, blue: 0/255)
    static let goldDim    = Color(red: 139/255, green: 117/255, blue: 53/255)
    static let bgDeep     = Color(red: 13/255, green: 17/255, blue: 23/255)
    static let bgSurface  = Color(red: 22/255, green: 27/255, blue: 34/255)
    static let bgElevated = Color(red: 28/255, green: 35/255, blue: 51/255)
    static let bgHover    = Color(red: 33/255, green: 38/255, blue: 45/255)
    static let green  = Color(red: 63/255, green: 185/255, blue: 80/255)
    static let blue   = Color(red: 88/255, green: 166/255, blue: 255/255)
    static let red    = Color(red: 248/255, green: 81/255, blue: 73/255)
    static let purple = Color(red: 210/255, green: 168/255, blue: 255/255)
    static let orange = Color(red: 240/255, green: 136/255, blue: 62/255)
    static let cyan   = Color(red: 0, green: 200/255, blue: 200/255)
    static let gray   = Color(red: 139/255, green: 148/255, blue: 158/255)
    static let textPrimary   = Color(red: 230/255, green: 237/255, blue: 243/255)
    static let textSecondary = Color(red: 139/255, green: 148/255, blue: 158/255)
    static let textTertiary  = Color(red: 110/255, green: 118/255, blue: 129/255)
    static let border = Color(red: 48/255, green: 54/255, blue: 61/255)
}

extension View {
    func stampedeCard() -> some View {
        self.background(StampedeColors.bgSurface).cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(StampedeColors.border, lineWidth: 1))
    }
    func goldGlow() -> some View {
        self.shadow(color: StampedeColors.gold.opacity(0.15), radius: 10)
    }
}
