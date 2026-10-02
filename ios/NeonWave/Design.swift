import SwiftUI

enum NW {
    static let background = Color(red: 0.035, green: 0.035, blue: 0.045)
    static let surface = Color(white: 0.10)
    static let elevated = Color(white: 0.16)
    static let blue = Color(red: 0.12, green: 0.52, blue: 1.0)
    static let cyan = Color(red: 0.20, green: 0.83, blue: 0.91)
    static let violet = Color(red: 0.58, green: 0.35, blue: 1.0)
    static let accent = Color(red: 0.12, green: 0.52, blue: 1.0) // Vibrant Electric Blue
    static let muted = Color(white: 0.56)
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
    var accent: Color = NW.accent
    var body: some View {
        ZStack {
            NW.background
            RadialGradient(colors: [accent.opacity(0.12), .clear], center: .init(x: 0.88, y: 0.05), startRadius: 20, endRadius: 420)
            RadialGradient(colors: [Color.purple.opacity(0.06), .clear], center: .init(x: 0.08, y: 0.85), startRadius: 20, endRadius: 360)
            LinearGradient(colors: [.clear, Color.black.opacity(0.40)], startPoint: .top, endPoint: .bottom)
        }.ignoresSafeArea()
    }
}

extension View {
    func premiumPanel(radius: CGFloat = 20) -> some View {
        self
            .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(.white.opacity(0.07), lineWidth: 0.5))
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
            .shadow(color: NW.blue.opacity(0.35), radius: size * 0.14)
            .accessibilityHidden(true)
    }
}

struct CoverArt: View {
    var track: Track? = nil
    var index = 0
    var symbol: String? = nil
    var imageURL: URL? = nil
    var remoteURL: String? = nil
    var radius: CGFloat = 12
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
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(.white.opacity(0.07), lineWidth: 0.5))
        .accessibilityHidden(true)
    }

    @ViewBuilder private func placeholder(geo: GeometryProxy) -> some View {
        let colors = NW.colors[(track?.colorIndex ?? index) % NW.colors.count]
        ZStack {
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: geo.size.width * 0.36, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: geo.size.width * 0.36, weight: .light))
                    .foregroundStyle(.white.opacity(0.75))
            }
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
            HStack(spacing: 9) {
                if loading { ProgressView().tint(.black) }
                else if let symbol { Image(systemName: symbol).font(.system(size: 15, weight: .bold)) }
                Text(title).font(.system(size: 16, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .shadow(color: .black.opacity(0.2), radius: 10, y: 5)
        }
        .foregroundStyle(.black)
        .buttonStyle(PressStyle())
        .disabled(loading)
    }
}

struct PressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

struct SectionHeading: View {
    let title: String
    var eyebrow: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let eyebrow {
                Text(eyebrow.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(NW.muted)
            }
            Text(title)
                .font(.system(size: 22, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
            Image(systemName: symbol)
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(NW.accent)
                .frame(width: 80, height: 80)
                .background(NW.accent.opacity(0.12), in: Circle())
            Text(title).font(.title3.weight(.bold))
            Text(description)
                .font(.subheadline)
                .foregroundStyle(NW.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 10)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.subheadline.bold())
                    .tint(NW.accent)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 26)
        .padding(.vertical, 40)
    }
}

struct IconButton: View {
    let symbol: String
    let label: String
    var action: () -> Void
    var body: some View {
        Button(action: {
            Haptic.light()
            action()
        }) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .medium))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(label)
    }
}

enum Haptic {
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    static func medium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
    static func heavy() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

struct FluidMeshBackground: View {
    let colors: [Color]
    let isPlaying: Bool
    var reduceMotion: Bool = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1/24, paused: !isPlaying || reduceMotion)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let pulse = 1.0 + 0.06 * sin(time * 0.7)

            ZStack {
                NW.background

                // Top leading dynamic orb
                Circle()
                    .fill(colors[0].opacity(0.38))
                    .frame(width: 380, height: 380)
                    .blur(radius: 75)
                    .offset(x: -80 + 50 * cos(time * 0.25), y: -140 + 40 * sin(time * 0.35))
                    .scaleEffect(pulse)

                // Top trailing accent orb
                Circle()
                    .fill((colors.count > 1 ? colors[1] : NW.accent).opacity(0.30))
                    .frame(width: 340, height: 340)
                    .blur(radius: 80)
                    .offset(x: 100 + 45 * sin(time * 0.3), y: -50 + 35 * cos(time * 0.22))
                    .scaleEffect(1.8 - pulse)

                // Bottom center floating orb
                Circle()
                    .fill(Color.purple.opacity(0.22))
                    .frame(width: 300, height: 300)
                    .blur(radius: 70)
                    .offset(x: 40 * sin(time * 0.4), y: 160 + 30 * cos(time * 0.35))

                // Smooth darkening overlay for readability
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.20),
                        Color.black.opacity(0.40),
                        NW.background.opacity(0.92)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .ignoresSafeArea()
    }
}
