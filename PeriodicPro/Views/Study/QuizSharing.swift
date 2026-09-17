import LinkPresentation
import SwiftUI
import UIKit

/// The card a shared quiz link shows in Messages, Mail and anywhere else that
/// draws a rich link.
///
/// Rendered from this view rather than bundled as a raster, so it carries the
/// quiz's own title in the app's own type at whatever size the renderer is
/// asked for, and there is no 1200 × 630 PNG in the app bundle that has to be
/// kept in step with the design. The website serves a matching static image
/// for the same link, for services that fetch the page instead.
struct QuizShareCard: View {
    let title: String
    let subtitle: String

    /// The proportions every link-preview surface expects.
    static let size = CGSize(width: 1200, height: 630)

    /// Elemora's mark: four columns by three rows of tiles, one of them gold.
    private static let tealTiles: [(Int, Int)] = [
        (0, 0), (0, 1), (2, 1), (3, 1), (0, 2), (1, 2), (2, 2), (3, 2),
    ]
    private static let goldTile = (3, 0)
    private static let teal = Color(hex: 0x1B808D)
    private static let gold = Color(hex: 0xD5A854)
    private static let field = Color(hex: 0xF7F5F0)
    private static let ink = Color(hex: 0x111C21)

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [Self.field, Color(hex: 0xEAF0F2)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // A faint enlargement of the mark, bled off the right edge, so the
            // card reads as Elemora even at thumbnail size.
            mark(tile: 150, gap: 22)
                .opacity(0.10)
                .offset(x: 820, y: 120)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 28) {
                    mark(tile: 26, gap: 4)
                    Text("ELEMORA")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .kerning(6)
                        .foregroundStyle(Self.teal)
                }

                Spacer(minLength: 0)

                Text(title)
                    .font(.system(size: 78, weight: .bold, design: .rounded))
                    .foregroundStyle(Self.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
                    .multilineTextAlignment(.leading)

                Text(subtitle)
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(Self.ink.opacity(0.6))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.top, 18)

                Spacer(minLength: 0)

                Text("Elemora Quiz")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 30)
                    .padding(.vertical, 16)
                    .background { Capsule().fill(Self.teal) }
            }
            .padding(72)
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }

    private func mark(tile: CGFloat, gap: CGFloat) -> some View {
        let pitch = tile + gap
        return ZStack(alignment: .topLeading) {
            Color.clear.frame(width: pitch * 4 - gap, height: pitch * 3 - gap)
            ForEach(Array(Self.tealTiles.enumerated()), id: \.offset) { _, position in
                square(tile: tile, color: Self.teal)
                    .offset(x: CGFloat(position.0) * pitch, y: CGFloat(position.1) * pitch)
            }
            square(tile: tile, color: Self.gold)
                .offset(x: CGFloat(Self.goldTile.0) * pitch, y: CGFloat(Self.goldTile.1) * pitch)
        }
    }

    private func square(tile: CGFloat, color: Color) -> some View {
        RoundedRectangle(cornerRadius: tile * 0.22, style: .continuous)
            .fill(color)
            .frame(width: tile, height: tile)
    }
}

/// Renders the share card once, when somebody actually shares something.
enum QuizShareImage {
    /// The card as a `UIImage`, or `nil` if the renderer produced nothing —
    /// in which case the share sheet simply shows the link without a picture.
    @MainActor
    static func render(title: String, subtitle: String) -> UIImage? {
        let renderer = ImageRenderer(content: QuizShareCard(title: title, subtitle: subtitle))
        // Two points per pixel is plenty for a preview and keeps the item a
        // couple of hundred kilobytes rather than a couple of megabytes.
        renderer.scale = 1
        renderer.isOpaque = true
        return renderer.uiImage
    }
}

/// Supplies the quiz link, and the metadata that makes it look like something.
///
/// `ShareLink` alone hands Messages a bare URL, which is what produced the
/// blank white document tile. An activity item source can answer
/// `activityViewControllerLinkMetadata`, which is the documented way to give
/// the share sheet a title and an image before anything has been sent.
final class QuizShareItemSource: NSObject, UIActivityItemSource {
    private let url: URL
    private let title: String
    private let subtitle: String
    private let image: UIImage?

    init(url: URL, title: String, subtitle: String, image: UIImage?) {
        self.url = url
        self.title = title
        self.subtitle = subtitle
        self.image = image
    }

    /// "Rate the Elements — Elemora Quiz".
    var previewTitle: String { "\(title) — Elemora Quiz" }

    func activityViewControllerPlaceholderItem(_ controller: UIActivityViewController) -> Any {
        url
    }

    func activityViewController(
        _ controller: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        url
    }

    func activityViewController(
        _ controller: UIActivityViewController,
        subjectForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        previewTitle
    }

    func activityViewControllerLinkMetadata(
        _ controller: UIActivityViewController
    ) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.originalURL = url
        metadata.url = url
        metadata.title = previewTitle
        if let image {
            metadata.imageProvider = NSItemProvider(object: image)
            metadata.iconProvider = NSItemProvider(object: image)
        }
        return metadata
    }
}

/// The system share sheet, with the branded metadata attached.
struct QuizShareSheet: UIViewControllerRepresentable {
    let url: URL
    let title: String
    let subtitle: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let source = QuizShareItemSource(
            url: url,
            title: title,
            subtitle: subtitle,
            image: QuizShareImage.render(title: title, subtitle: subtitle)
        )
        return UIActivityViewController(activityItems: [source], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// What a shared quiz link opens onto: the quiz, already saved.
///
/// Nobody sees JSON, a file, a document picker or an encoded payload. The link
/// opened Elemora, the quiz was validated and saved before this appeared, and
/// the only two things left to decide are whether to play it now or look at it
/// later.
struct SharedQuizResultView: View {
    let outcome: QuizImportOutcome
    let onStart: (SavedQuiz) -> Void
    let onViewAll: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.l) {
                Spacer(minLength: 0)
                switch outcome {
                case .saved(let quiz):
                    success(quiz: quiz, title: "Quiz saved")
                case .alreadySaved(let quiz):
                    success(quiz: quiz, title: "Already in My Quizzes")
                case .failed(let message):
                    EmptyStateView(
                        symbolName: "exclamationmark.triangle",
                        title: "That quiz could not be opened",
                        message: message
                    )
                    .accessibilityIdentifier("sharedQuiz.failed")
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Theme.Spacing.screenMargin)
            .background(AppColor.canvas)
            .navigationTitle("Shared quiz")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("sharedQuiz.done")
                }
            }
        }
        .tint(AppColor.accent)
        .presentationDetents([.medium, .large])
        .accessibilityIdentifier("sharedQuiz.screen")
    }

    private func success(quiz: SavedQuiz, title: String) -> some View {
        VStack(spacing: Theme.Spacing.l) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(AppColor.positive)
                .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text(title)
                    .font(.system(.title2, weight: .bold))
                    .foregroundStyle(AppColor.primaryText)
                    .accessibilityIdentifier("sharedQuiz.title")
                Text(quiz.name)
                    .font(.system(.title3, weight: .semibold))
                    .foregroundStyle(AppColor.primaryText)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("sharedQuiz.name")
                Text(quiz.configuration.summary)
                    .font(AppFont.footnote)
                    .foregroundStyle(AppColor.secondaryText)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: Theme.Spacing.s) {
                Button {
                    Haptics.tap()
                    onStart(quiz)
                    dismiss()
                } label: {
                    Text("Start Quiz")
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 52)
                        .background {
                            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                                .fill(AppColor.accent)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("sharedQuiz.start")

                Button {
                    Haptics.tap()
                    onViewAll()
                    dismiss()
                } label: {
                    Text("View in My Quizzes")
                        .font(.system(.body, weight: .medium))
                        .foregroundStyle(AppColor.accent)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: Theme.minimumTouchTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("sharedQuiz.viewAll")
            }
            .padding(.top, Theme.Spacing.s)
        }
    }
}
