import SwiftUI

enum NW {
    static let background = Color(red: 0.018, green: 0.022, blue: 0.048)
    static let surface = Color(red: 0.060, green: 0.068, blue: 0.105)
    static let elevated = Color(red: 0.085, green: 0.095, blue: 0.145)
    static let blue = Color(red: 0.38, green: 0.50, blue: 1)
    static let cyan = Color(red: 0.20, green: 0.83, blue: 0.91)
    static let violet = Color(red: 0.58, green: 0.35, blue: 1)
    static let muted = Color(red: 0.61, green: 0.64, blue: 0.73)
    static let colors: [[Color]] = [
        [.init(red: 0.27, green: 0.40, blue: 1), .init(red: 0.08, green: 0.10, blue: 0.34)],
        [.init(red: 0.94, green: 0.42, blue: 0.30), .init(red: 0.31, green: 0.08, blue: 0.19)],
        [.init(red: 0.54, green: 0.35, blue: 0.95), .init(red: 0.17, green: 0.08, blue: 0.28)],
        [.init(red: 0.18, green: 0.67, blue: 0.58), .init(red: 0.04, green: 0.20, blue: 0.24)],
        [.init(red: 0.96, green: 0.70, blue: 0.32), .init(red: 0.36, green: 0.16, blue: 0.12)],
        [.init(red: 0.85, green: 0.36, blue: 0.61), .init(red: 0.26, green: 0.09, blue: 0.29)]
    ]
}

struct PremiumBackdrop: View {
    var accent: Color = NW.blue
    var body: some View {
        ZStack {
            NW.background
            RadialGradient(colors: [accent.opacity(0.24), .clear], center: .init(x: 0.88, y: 0.05), startRadius: 0, endRadius: 360)
            RadialGradient(colors: [NW.cyan.opacity(0.12), .clear], center: .init(x: 0.05, y: 0.82), startRadius: 10, endRadius: 330)
            LinearGradient(colors: [.clear, Color.black.opacity(0.22)], startPoint: .top, endPoint: .bottom)
        }.ignoresSafeArea()
    }
}

extension View {
    func premiumPanel(radius: CGFloat = 24) -> some View {
        self
            .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(.white.opacity(0.09), lineWidth: 1))
    }
}

struct WaveMark: View {
    var size: CGFloat = 34
    var body: some View {
        Image("NeonLogo")
            .resizable()
            .renderingMode(.original)
            .scaledToFit()
            .frame(width: size, height: size)
            .shadow(color: NW.blue.opacity(0.48), radius: size * 0.16)
            .accessibilityHidden(true)
    }
}

struct CoverArt: View {
    var track: Track? = nil
    var index = 0
    var symbol: String? = nil
    var imageURL: URL? = nil
    var remoteURL: String? = nil
    var radius: CGFloat = 20
    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let imageURL, let image = UIImage(contentsOfFile: imageURL.path) {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                } else if let remote = (remoteURL ?? track?.artworkURL), let url = URL(string: remote) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                                .frame(width: geo.size.width, height: geo.size.height)
                                .clipped()
                        default:
                            placeholder(geo: geo)
                        }
                    }
                } else {
                    placeholder(geo: geo)
                }
            }.frame(width: geo.size.width, height: geo.size.height).clipped()
        }.aspectRatio(1, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .accessibilityHidden(true)
    }

    @ViewBuilder private func placeholder(geo: GeometryProxy) -> some View {
        let colors = NW.colors[(track?.colorIndex ?? index) % NW.colors.count]
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
        Circle().stroke(.white.opacity(0.12), lineWidth: geo.size.width * 0.13)
            .frame(width: geo.size.width * 0.85).offset(x: geo.size.width * 0.18, y: geo.size.height * 0.16)
        Circle().stroke(.white.opacity(0.16), lineWidth: 1)
            .frame(width: geo.size.width * 0.64).offset(x: geo.size.width * 0.18, y: geo.size.height * 0.16)
        if let symbol {
            Image(systemName: symbol).font(.system(size: geo.size.width * 0.32, weight: .medium)).foregroundStyle(.white)
        } else {
            WaveMark(size: geo.size.width * 0.26).rotationEffect(.degrees(-12))
        }
    }
}

struct PrimaryButton: View {
    let title: String
    var symbol: String? = nil
    var loading = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if loading { ProgressView().tint(.white) }
                else if let symbol { Image(systemName: symbol) }
                Text(title).font(.system(.body, design: .rounded, weight: .bold))
            }.frame(maxWidth: .infinity).frame(minHeight: 56)
                .background(LinearGradient(colors: [NW.blue, NW.violet], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.18)))
                .shadow(color: NW.blue.opacity(0.24), radius: 18, y: 9)
        }.foregroundStyle(.white).buttonStyle(PressStyle()).disabled(loading)
    }
}

struct PressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.3), value: configuration.isPressed)
    }
}

struct SectionHeading: View {
    let title: String
    var eyebrow: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let eyebrow { Text(eyebrow.uppercased()).font(.system(size: 10, weight: .bold)).tracking(2.5).foregroundStyle(NW.muted) }
            Text(title).font(.system(size: 25, weight: .bold, design: .rounded)).tracking(-0.7).foregroundStyle(.white)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct EmptyLibrary: View {
    let symbol: String
    let title: String
    let description: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: symbol).font(.system(size: 34, weight: .light)).foregroundStyle(NW.blue)
                .frame(width: 86, height: 86).background(NW.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 28))
            Text(title).font(.title3.bold())
            Text(description).font(.subheadline).foregroundStyle(NW.muted).multilineTextAlignment(.center)
            if let actionTitle, let action { Button(actionTitle, action: action).font(.subheadline.bold()).tint(NW.blue).padding(.top, 4) }
        }.frame(maxWidth: .infinity).padding(.horizontal, 26).padding(.vertical, 36)
    }
}

struct IconButton: View {
    let symbol: String
    let label: String
    var action: () -> Void
    var body: some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 19, weight: .medium)).frame(width: 46, height: 46) }
            .buttonStyle(PressStyle()).accessibilityLabel(label)
    }
}
