import SwiftUI

struct AuthorityBadge: View {
    let authority: SourceAuthority

    var body: some View {
        Label(authority.rawValue, systemImage: authority.symbol)
            .font(.caption.bold())
            .foregroundStyle(tint)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(.thinMaterial, in: Capsule())
            .accessibilityLabel("Source authority: \(authority.rawValue). \(authority.explanation)")
    }

    private var tint: Color {
        switch authority {
        case .approved: .green
        case .manufacturer: .blue
        case .training: .orange
        case .experience: .purple
        }
    }
}
