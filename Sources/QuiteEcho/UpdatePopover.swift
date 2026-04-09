import AppKit
import SwiftUI

// MARK: - Update Popover

struct UpdatePopoverView: View {
    @ObservedObject var vm: MainViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch vm.updateState {
            case .available(let version, let notes):
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.circle.fill")
                        .foregroundStyle(.orange)
                    Text("v\(version) Available")
                        .font(.system(size: 13, weight: .semibold))
                }

                if let notes, !notes.isEmpty {
                    ScrollView {
                        HTMLTextView(html: notes, width: 272)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(10)
                    }
                    .frame(maxHeight: 220)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.4))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                HStack(spacing: 8) {
                    popoverTextButton("Skip") { vm.onUpdateSkip?(); vm.showUpdatePopover = false }
                    Spacer()
                    popoverTextButton("Later") { vm.onUpdateDismiss?(); vm.showUpdatePopover = false }
                    popoverPrimaryButton("Install Update") { vm.onUpdateInstall?() }
                }

            case .downloading(let version, let progress):
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(.orange)
                    Text("Downloading v\(version)")
                        .font(.system(size: 13, weight: .semibold))
                }
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(.orange)
                HStack {
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                }

            case .extracting(let version, let progress):
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(.orange)
                    Text("Preparing v\(version)")
                        .font(.system(size: 13, weight: .semibold))
                }
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(.orange)

            case .readyToInstall(let version):
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(.green)
                    Text("v\(version) Ready")
                        .font(.system(size: 13, weight: .semibold))
                }
                Text("Relaunch to finish installing.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    popoverPrimaryButton("Install & Relaunch") { vm.onUpdateInstallAndRelaunch?() }
                }

            case .installing(let version):
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Installing v\(version)…")
                        .font(.system(size: 13))
                }

            case .checking:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Checking for updates…")
                        .font(.system(size: 13))
                }

            case .notFound:
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("You're up to date")
                        .font(.system(size: 13))
                }

            case .error(let msg):
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                    Text(msg)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

            case .idle:
                EmptyView()
            }
        }
        .padding(14)
        .frame(width: 320)
    }

    private func popoverTextButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
    }

    private func popoverPrimaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Color.orange)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .focusable(false)
    }
}

// MARK: - HTML Text View

/// Self-sizing NSTextView that reports its rendered content height via
/// intrinsicContentSize, so SwiftUI can lay it out without a wrapping
/// NSScrollView.
private final class SelfSizingTextView: NSTextView {
    override var intrinsicContentSize: NSSize {
        guard let container = textContainer, let layoutManager else {
            return super.intrinsicContentSize
        }
        layoutManager.ensureLayout(for: container)
        let used = layoutManager.usedRect(for: container).size
        return NSSize(width: NSView.noIntrinsicMetric, height: ceil(used.height))
    }
}

/// Renders release notes HTML using NSTextView (which honors tabStops).
/// Parses HTML via NSAttributedString, then rescales fonts and rewrites
/// paragraph styles for tight, consistent formatting.
struct HTMLTextView: NSViewRepresentable {
    let html: String
    let width: CGFloat

    func makeNSView(context: Context) -> NSTextView {
        let textView = SelfSizingTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        if let container = textView.textContainer {
            container.lineFragmentPadding = 0
            container.widthTracksTextView = true
            container.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        }
        textView.linkTextAttributes = [
            .foregroundColor: NSColor.linkColor,
            .cursor: NSCursor.pointingHand,
        ]
        return textView
    }

    func updateNSView(_ textView: NSTextView, context: Context) {
        if let container = textView.textContainer {
            container.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        }
        textView.frame.size.width = width
        if let attr = parseHTML() {
            textView.textStorage?.setAttributedString(attr)
        } else {
            textView.string = html
        }
        textView.invalidateIntrinsicContentSize()
    }

    private func parseHTML() -> NSAttributedString? {
        guard let data = html.data(using: .utf8),
              let ns = try? NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue,
                ],
                documentAttributes: nil
              )
        else { return nil }

        let mutable = NSMutableAttributedString(attributedString: ns)
        let fullRange = NSRange(location: 0, length: mutable.length)

        // Rescale fonts: preserve bold/italic traits but cap heading sizes.
        mutable.enumerateAttribute(.font, in: fullRange) { value, range, _ in
            let original = value as? NSFont ?? NSFont.systemFont(ofSize: 11)
            let traits = original.fontDescriptor.symbolicTraits
            let isBold = traits.contains(.bold)
            let isLarge = original.pointSize >= 16  // h1/h2/h3 are 18-24pt
            let size: CGFloat = isLarge ? 12 : 11
            let weight: NSFont.Weight = (isBold || isLarge) ? .semibold : .regular
            var newFont = NSFont.systemFont(ofSize: size, weight: weight)
            if traits.contains(.italic) {
                let desc = newFont.fontDescriptor.withSymbolicTraits(.italic)
                newFont = NSFont(descriptor: desc, size: size) ?? newFont
            }
            mutable.addAttribute(.font, value: newFont, range: range)
        }

        // Rewrite paragraph styles: tight spacing, compact bullet indentation.
        mutable.enumerateAttribute(.paragraphStyle, in: fullRange) { value, range, _ in
            let style = (value as? NSParagraphStyle).flatMap { $0.mutableCopy() as? NSMutableParagraphStyle }
                ?? NSMutableParagraphStyle()
            style.lineSpacing = 2
            style.paragraphSpacing = 4
            style.paragraphSpacingBefore = 0
            // Detect bullet list paragraphs (HTML parser marks them with head indent)
            if style.headIndent > 0 || !style.tabStops.isEmpty {
                style.firstLineHeadIndent = 0
                style.headIndent = 14
                style.tabStops = [
                    NSTextTab(textAlignment: .left, location: 4),
                    NSTextTab(textAlignment: .left, location: 14),
                ]
                style.defaultTabInterval = 14
            }
            mutable.addAttribute(.paragraphStyle, value: style, range: range)
        }

        // Force label color for non-link text so dark mode renders correctly.
        mutable.enumerateAttribute(.link, in: fullRange) { link, range, _ in
            if link == nil {
                mutable.addAttribute(.foregroundColor, value: NSColor.labelColor, range: range)
            }
        }

        return mutable
    }
}
