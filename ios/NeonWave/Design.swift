import SwiftUI

enum NW {
    static let background = Color(red: 0.035, green: 0.043, blue: 0.07)
    static let surface = Color(red: 0.075, green: 0.086, blue: 0.12)
    static let blue = Color(red: 0.35, green: 0.48, blue: 1)
    static let muted = Color(red: 0.57, green: 0.60, blue: 0.68)
    static let colors: [[Color]] = [
        [.init(red: 0.27, green: 0.40, blue: 1), .init(red: 0.08, green: 0.10, blue: 0.34)],
        [.init(red: 0.94, green: 0.42, blue: 0.30), .init(red: 0.31, green: 0.08, blue: 0.19)],
        [.init(red: 0.54, green: 0.35, blue: 0.95), .init(red: 0.17, green: 0.08, blue: 0.28)],
        [.init(red: 0.18, green: 0.67, blue: 0.58), .init(red: 0.04, green: 0.20, blue: 0.24)],
        [.init(red: 0.96, green: 0.70, blue: 0.32), .init(red: 0.36, green: 0.16, blue: 0.12)],
        [.init(red: 0.85, green: 0.36, blue: 0.61), .init(red: 0.26, green: 0.09, blue: 0.29)]
    ]
}

struct WaveMark: View {
    var size: CGFloat = 34
    var body: some View {
        HStack(spacing: size * 0.09) {
            ForEach(Array([0.35, 0.7, 1.0, 0.56, 0.82].enumerated()), id: \.offset) { _, height in
                Capsule().fill(.white).frame(width: size * 0.12, height: size * height)
            }
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}

struct CoverArt: View {
    var track: Track? = nil
    var index = 0
    var symbol: String? = nil
    var imageURL: URL? = nil
    var radius: CGFloat = 20
    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let imageURL, let image = UIImage(contentsOfFile: imageURL.path) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
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
            }.frame(width: geo.size.width, height: geo.size.height).clipped()
        }.aspectRatio(1, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .accessibilityHidden(true)
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
            }.frame(maxWidth: .infinity).padding(.vertical, 18)
                .background(NW.blue.gradient, in: RoundedRectangle(cornerRadius: 18))
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
            Text(title).font(.system(.title2, design: .rounded, weight: .bold)).foregroundStyle(.white)
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
