import UIKit
import UniformTypeIdentifiers

@MainActor
final class ShareViewController: UIViewController {
    private struct PreparedShare {
        var request: SharedImportRequest
        var imageData: [Data]
        var summary: String
    }

    private enum ShareState {
        case loading
        case saving
        case saved(String)
        case empty
        case failed(String)
    }

    private let iconBackground = UIView()
    private let iconView = UIImageView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let primaryButton = UIButton(type: .system)
    private let footerLabel = UILabel()

    private var didBeginSaving = false
    private var state: ShareState = .loading

    override func viewDidLoad() {
        super.viewDidLoad()
        configureInterface()
        preferredContentSize = CGSize(width: 0, height: 380)
        startSavingIfNeeded()
    }

    // MARK: - Interface

    private func configureInterface() {
        view.backgroundColor = Palette.background

        let content = UIStackView()
        content.axis = .vertical
        content.alignment = .center
        content.spacing = 16
        content.translatesAutoresizingMaskIntoConstraints = false

        iconBackground.backgroundColor = Palette.sage.withAlphaComponent(0.12)
        iconBackground.layer.cornerRadius = 36
        iconBackground.translatesAutoresizingMaskIntoConstraints = false
        iconBackground.widthAnchor.constraint(equalToConstant: 72).isActive = true
        iconBackground.heightAnchor.constraint(equalToConstant: 72).isActive = true

        iconView.image = UIImage(systemName: "fork.knife")
        iconView.tintColor = Palette.sage
        iconView.contentMode = .scaleAspectFit
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 27, weight: .light)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.isAccessibilityElement = false
        iconBackground.addSubview(iconView)
        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: iconBackground.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconBackground.centerYAnchor)
        ])

        spinner.color = Palette.sage
        spinner.hidesWhenStopped = true
        spinner.accessibilityLabel = "Saving to Mise"

        titleLabel.font = Self.serifFont(for: .title1)
        titleLabel.textColor = Palette.ink
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.accessibilityTraits = .header

        detailLabel.font = UIFont.preferredFont(forTextStyle: .subheadline)
        detailLabel.textColor = Palette.secondaryInk
        detailLabel.textAlignment = .center
        detailLabel.numberOfLines = 0
        detailLabel.adjustsFontForContentSizeCategory = true

        var configuration = UIButton.Configuration.filled()
        configuration.title = "Saving…"
        configuration.baseBackgroundColor = Palette.ink
        configuration.baseForegroundColor = Palette.background
        configuration.cornerStyle = .large
        configuration.buttonSize = .large
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 20, bottom: 14, trailing: 20)
        primaryButton.configuration = configuration
        primaryButton.titleLabel?.adjustsFontForContentSizeCategory = true
        primaryButton.addTarget(self, action: #selector(finishTapped), for: .touchUpInside)
        primaryButton.isEnabled = false
        primaryButton.accessibilityIdentifier = "shareDoneButton"

        footerLabel.text = "Mise · Save anything. Cook without the clutter."
        footerLabel.font = UIFont.preferredFont(forTextStyle: .caption2)
        footerLabel.textColor = Palette.secondaryInk.withAlphaComponent(0.8)
        footerLabel.textAlignment = .center
        footerLabel.adjustsFontForContentSizeCategory = true

        content.addArrangedSubview(iconBackground)
        content.addArrangedSubview(spinner)
        content.addArrangedSubview(titleLabel)
        content.addArrangedSubview(detailLabel)
        content.setCustomSpacing(24, after: iconBackground)
        content.setCustomSpacing(6, after: titleLabel)
        content.setCustomSpacing(22, after: detailLabel)
        content.addArrangedSubview(primaryButton)
        content.addArrangedSubview(footerLabel)
        content.setCustomSpacing(18, after: primaryButton)

        view.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 28),
            content.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -28),
            content.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            content.topAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            content.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            primaryButton.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            primaryButton.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            primaryButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 50)
        ])

        setState(.loading)
    }

    private static func serifFont(for textStyle: UIFont.TextStyle) -> UIFont {
        let base = UIFont.preferredFont(forTextStyle: textStyle)
        guard let descriptor = base.fontDescriptor.withDesign(.serif) else { return base }
        return UIFont(descriptor: descriptor, size: 0)
    }

    private func setState(_ newState: ShareState) {
        state = newState
        let update = { [weak self] in
            guard let self else { return }
            self.apply(newState)
        }
        if view.window == nil {
            update()
        } else {
            UIView.transition(
                with: view,
                duration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.18,
                options: .transitionCrossDissolve,
                animations: update
            )
        }
    }

    private func apply(_ state: ShareState) {
        switch state {
        case .loading:
            spinner.startAnimating()
            iconView.image = UIImage(systemName: "fork.knife")
            iconView.tintColor = Palette.sage
            titleLabel.text = "Preparing your recipe"
            detailLabel.text = "Reading what you shared and keeping it on this device."
            setPrimaryTitle("Saving…", enabled: false)

        case .saving:
            spinner.startAnimating()
            iconView.image = UIImage(systemName: "square.and.arrow.down")
            iconView.tintColor = Palette.sage
            titleLabel.text = "Saving to Mise"
            detailLabel.text = "Adding this to your import queue."
            setPrimaryTitle("Saving…", enabled: false)

        case .saved(let summary):
            spinner.stopAnimating()
            iconView.image = UIImage(systemName: "checkmark")
            iconView.tintColor = Palette.positive
            iconBackground.backgroundColor = Palette.positive.withAlphaComponent(0.12)
            titleLabel.text = "Saved for review"
            detailLabel.text = summary
            setPrimaryTitle("Done", enabled: true)
            UIAccessibility.post(notification: .announcement, argument: "Saved to Mise for review")

        case .empty:
            spinner.stopAnimating()
            iconView.image = UIImage(systemName: "questionmark")
            iconView.tintColor = Palette.secondaryInk
            titleLabel.text = "Nothing to save"
            detailLabel.text = "Share a public recipe link, some recipe text, or up to six screenshots."
            setPrimaryTitle("Close", enabled: true)

        case .failed(let message):
            spinner.stopAnimating()
            iconView.image = UIImage(systemName: "exclamationmark")
            iconView.tintColor = Palette.accent
            iconBackground.backgroundColor = Palette.accent.withAlphaComponent(0.12)
            titleLabel.text = "Couldn’t save this"
            detailLabel.text = message
            setPrimaryTitle("Close", enabled: true)
            UIAccessibility.post(notification: .announcement, argument: message)
        }
    }

    private func setPrimaryTitle(_ title: String, enabled: Bool) {
        var configuration = primaryButton.configuration
        configuration?.title = title
        configuration?.baseBackgroundColor = enabled ? Palette.ink : Palette.ink.withAlphaComponent(0.35)
        primaryButton.configuration = configuration
        primaryButton.isEnabled = enabled
    }

    // MARK: - Saving

    private func startSavingIfNeeded() {
        guard !didBeginSaving else { return }
        didBeginSaving = true
        Task { await saveSharedContent() }
    }

    private func saveSharedContent() async {
        setState(.loading)

        guard let prepared = await prepareShare() else {
            setState(.empty)
            return
        }

        setState(.saving)
        guard let store = SharedImportStore() else {
            setState(.failed("Mise couldn’t reach its shared storage. Open Mise once, then try sharing again."))
            return
        }

        do {
            try store.enqueue(prepared.request, imageData: prepared.imageData)
            setState(.saved(prepared.summary))
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            setState(.failed("Mise couldn’t add this to its import queue. Open Mise once, then try again."))
        }
    }

    private func prepareShare() async -> PreparedShare? {
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        let providers = items.flatMap { $0.attachments ?? [] }

        if let url = await firstWebURL(in: providers) {
            let sharedText = await firstText(in: providers) ?? items.compactMap(\.attributedContentText?.string).first
            let request = SharedImportRequest(
                kind: .url,
                urlString: url.absoluteString,
                text: normalized(sharedText)
            )
            return PreparedShare(
                request: request,
                imageData: [],
                summary: "Open Mise to review this link before adding it to your library."
            )
        }

        let imageProviders = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.image.identifier)
        }
        if !imageProviders.isEmpty {
            var images: [Data] = []
            for provider in imageProviders.prefix(6) {
                if let data = await imageData(from: provider), let prepared = Self.compressedImageData(from: data) {
                    images.append(prepared)
                }
            }
            if !images.isEmpty {
                let request = SharedImportRequest(kind: .image, imageFilenames: [])
                return PreparedShare(
                    request: request,
                    imageData: images,
                    summary: "Open Mise to read \(images.count == 1 ? "this image" : "these images") on device and review the recipe."
                )
            }
        }

        if let text = await firstText(in: providers) ?? items.compactMap(\.attributedContentText?.string).first {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let request = SharedImportRequest(
                kind: .text,
                text: String(trimmed.prefix(120_000))
            )
            return PreparedShare(
                request: request,
                imageData: [],
                summary: "Open Mise to review the shared text before adding it to your library."
            )
        }

        return nil
    }

    private func firstWebURL(in providers: [NSItemProvider]) async -> URL? {
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            guard let url = await loadURL(from: provider) else { continue }
            guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
                continue
            }
            guard let host = url.host, !host.isEmpty else { continue }
            return url
        }
        return nil
    }

    private func firstText(in providers: [NSItemProvider]) async -> String? {
        let types = [UTType.plainText.identifier, UTType.text.identifier]
        for provider in providers {
            guard let type = types.first(where: { provider.hasItemConformingToTypeIdentifier($0) }) else { continue }
            if let text = await loadText(from: provider, typeIdentifier: type) {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return text
                }
            }
        }
        return nil
    }

    private func normalized(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(120_000))
    }

    // MARK: - Item loading

    private func loadURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                if let url = item as? URL {
                    continuation.resume(returning: url)
                } else if let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) {
                    continuation.resume(returning: url)
                } else if let string = item as? String,
                          let url = URL(string: string) {
                    continuation.resume(returning: url)
                } else if let string = (item as? NSString) as String?,
                          let url = URL(string: string) {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func loadText(from provider: NSItemProvider, typeIdentifier: String) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, _ in
                if let text = item as? String {
                    continuation.resume(returning: text)
                } else if let text = item as? NSAttributedString {
                    continuation.resume(returning: text.string)
                } else if let text = (item as? NSString) as String? {
                    continuation.resume(returning: text)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func imageData(from provider: NSItemProvider) async -> Data? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }

    private static func compressedImageData(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let longestSide = max(image.size.width, image.size.height)
        let maxDimension: CGFloat = 2400
        guard longestSide > maxDimension else {
            return image.jpegData(compressionQuality: 0.86)
        }
        let scale = maxDimension / longestSide
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: 0.86)
    }

    // MARK: - Completion

    @objc private func finishTapped() {
        switch state {
        case .loading, .saving:
            return
        default:
            extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        }
    }
}

// MARK: - Palette

private enum Palette {
    static let background = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 18/255, green: 17/255, blue: 15/255, alpha: 1)
            : UIColor(red: 247/255, green: 243/255, blue: 234/255, alpha: 1)
    }

    static let ink = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 242/255, green: 238/255, blue: 228/255, alpha: 1)
            : UIColor(red: 29/255, green: 36/255, blue: 30/255, alpha: 1)
    }

    static let secondaryInk = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 168/255, green: 163/255, blue: 151/255, alpha: 1)
            : UIColor(red: 107/255, green: 106/255, blue: 96/255, alpha: 1)
    }

    static let accent = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 214/255, green: 132/255, blue: 94/255, alpha: 1)
            : UIColor(red: 184/255, green: 92/255, blue: 56/255, alpha: 1)
    }

    static let sage = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 143/255, green: 166/255, blue: 137/255, alpha: 1)
            : UIColor(red: 83/255, green: 107/255, blue: 82/255, alpha: 1)
    }

    static let positive = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 133/255, green: 179/255, blue: 123/255, alpha: 1)
            : UIColor(red: 63/255, green: 112/255, blue: 68/255, alpha: 1)
    }
}
