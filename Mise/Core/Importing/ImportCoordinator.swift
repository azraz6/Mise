import Foundation
import Observation
import SwiftData
import UIKit

@MainActor
@Observable
final class ImportCoordinator {
    let store: RecipeStore
    let images: ImageStore
    let usage: UsageTracker
    let subscriptions: SubscriptionManager
    let fetcher: PageFetching
    let ocr: OCRService
    let sharedStore: SharedImportStore?

    private var tasks: [UUID: Task<Void, Never>] = [:]

    init(
        store: RecipeStore,
        images: ImageStore = .shared,
        usage: UsageTracker,
        subscriptions: SubscriptionManager,
        fetcher: PageFetching = WebsiteFetcher(),
        ocr: OCRService = .shared,
        sharedStore: SharedImportStore? = SharedImportStore()
    ) {
        self.store = store
        self.images = images
        self.usage = usage
        self.subscriptions = subscriptions
        self.fetcher = fetcher
        self.ocr = ocr
        self.sharedStore = sharedStore
    }

    // MARK: - Starting imports

    @discardableResult
    func startURLImport(rawInput: String, sharedText: String? = nil, sourceTypeOverride: RecipeSourceType? = nil) throws -> ImportJob {
        let url: URL
        switch SourceDetector.validatedURL(from: rawInput) {
        case .success(let validated): url = validated
        case .failure(let error): throw ImportFailure.invalidInput(error)
        }
        try ensureImportAllowance()
        let sourceType = sourceTypeOverride ?? SourceDetector.classify(url)
        let job = ImportJob(
            sourceType: sourceType,
            sourceURLString: url.absoluteString,
            method: .linkOnly,
            sourceText: sharedText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? sharedText : nil
        )
        job.displayTitle = url.host ?? "Imported link"
        job.status = .queued
        job.retryEligible = true
        store.context.insert(job)
        try store.saveContext()
        launch(job)
        return job
    }

    @discardableResult
    func startTextImport(
        text: String,
        sourceType: RecipeSourceType = .text,
        sourceURL: URL? = nil,
        sourceTitle: String = "",
        countUsage: Bool = true
    ) async throws -> ImportJob {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ImportFailure.invalidInput(.empty) }
        try ensureImportAllowance()
        let source = sourceType
        let job = ImportJob(
            sourceType: source,
            sourceURLString: sourceURL?.absoluteString,
            method: .textHeuristics,
            sourceText: trimmed
        )
        job.status = .queued
        job.displayTitle = sourceTitle.isEmpty ? "Pasted recipe" : sourceTitle
        job.retryEligible = true
        store.context.insert(job)
        try store.saveContext()
        launchText(job, countUsage: countUsage)
        return job
    }

    @discardableResult
    func startImageImport(images sourceImages: [UIImage], sourceType: RecipeSourceType = .screenshot) async throws -> ImportJob {
        guard !sourceImages.isEmpty else { throw ImportFailure.invalidInput(.empty) }
        try ensureImportAllowance()
        let encoded = await Task.detached(priority: .userInitiated) {
            sourceImages.compactMap { $0.jpegData(compressionQuality: 0.88) }
        }.value
        guard !encoded.isEmpty else { throw ImportFailure.imageUnavailable }

        var filenames: [String] = []
        for data in encoded {
            if let filename = try? images.storeScratchImage(data: data) {
                filenames.append(filename)
            }
        }
        guard !filenames.isEmpty else { throw ImportFailure.imageUnavailable }

        let job = ImportJob(
            sourceType: sourceType,
            method: .ocrHeuristics,
            scratchImageFilenames: filenames
        )
        job.status = .queued
        job.displayTitle = sourceType == .screenshot ? "Screenshot import" : "Photo import"
        job.retryEligible = true
        store.context.insert(job)
        try store.saveContext()
        launch(job)
        return job
    }

    @discardableResult
    func startSharedRequest(_ request: SharedImportRequest) async throws -> ImportJob? {
        switch request.kind {
        case .url:
            guard let raw = request.urlString else { return nil }
            return try startURLImport(rawInput: raw, sharedText: request.text)
        case .text:
            guard let text = request.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            if let url = SourceDetector.firstWebURL(in: text) {
                let looksLikeRecipeText = text.count > 240
                    && text.lowercased().contains("ingredient")
                if looksLikeRecipeText {
                    return try await startTextImport(text: text, sourceType: .sharedText, sourceURL: url)
                }
                return try startURLImport(rawInput: url.absoluteString, sharedText: text)
            }
            return try await startTextImport(text: text, sourceType: .sharedText)
        case .image:
            var uiImages: [UIImage] = []
            for filename in request.imageFilenames {
                guard let data = sharedStore?.imageData(for: filename),
                      let image = UIImage(data: data) else { continue }
                uiImages.append(image)
            }
            guard !uiImages.isEmpty else { throw ImportFailure.imageUnavailable }
            return try await startImageImport(images: uiImages)
        }
    }

    // MARK: - Processing

    func retry(_ job: ImportJob) {
        guard job.retryEligible || job.status == .failed else { return }
        guard usage.canStartAutomaticImport(isPremium: subscriptions.isPremium) else {
            job.status = .failed
            job.errorTitle = ImportFailure.importLimitReached.title
            job.errorMessage = ImportFailure.importLimitReached.message
            job.retryEligible = false
            job.markUpdated()
            try? store.saveContext()
            return
        }
        job.status = .queued
        job.errorTitle = nil
        job.errorMessage = nil
        job.retryEligible = false
        job.markUpdated()
        try? store.saveContext()
        launch(job)
    }

    func cancel(_ job: ImportJob) {
        tasks[job.id]?.cancel()
        tasks[job.id] = nil
        if job.status == .processing || job.status == .queued {
            job.status = .failed
            job.errorTitle = ImportFailure.cancelled.title
            job.errorMessage = ImportFailure.cancelled.message
            job.retryEligible = true
            job.markUpdated()
            try? store.saveContext()
        }
    }

    func selectDraft(_ index: Int, in job: ImportJob) {
        guard job.drafts.indices.contains(index) else { return }
        job.selectedDraftIndex = index
        job.markUpdated()
        if let draft = job.selectedDraft {
            job.displayTitle = draft.displayTitle
            job.status = draft.hasCoreContent ? .extracted : .needsReview
        }
        try? store.saveContext()
    }

    func saveLinkPlaceholder(for job: ImportJob) async throws -> Recipe {
        let title: String
        if job.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            title = job.sourceType.displayName + " link"
        } else {
            title = job.displayTitle
        }
        let draft = RecipeDraft(
            title: title,
            sourceTitle: title,
            sourceURLString: job.sourceURLString,
            sourceType: job.sourceType,
            extractionMethod: .linkOnly,
            confidence: .unverified,
            warnings: ["Only the source link was saved. Add ingredients and steps before cooking."]
        )
        let recipe = try await store.save(draft: draft)
        markCompleted(job, recipe: recipe)
        return recipe
    }

    func markCompleted(_ job: ImportJob, recipe: Recipe) {
        job.status = .completed
        job.completedRecipeID = recipe.id
        job.displayTitle = recipe.title
        job.errorTitle = nil
        job.errorMessage = nil
        job.retryEligible = false
        job.markUpdated()
        for filename in job.scratchImageFilenames {
            images.deleteScratchImage(named: filename)
        }
        job.scratchImageFilenames = []
        try? store.saveContext()
    }

    func delete(_ job: ImportJob) {
        tasks[job.id]?.cancel()
        tasks[job.id] = nil
        store.deleteImportJob(job)
    }

    // MARK: - Workers

    private func launchText(_ job: ImportJob, countUsage: Bool) {
        tasks[job.id]?.cancel()
        tasks[job.id] = Task { [weak self] in
            guard let self else { return }
            await self.processText(job, countUsage: countUsage)
            self.tasks[job.id] = nil
        }
    }

    private func launch(_ job: ImportJob) {
        tasks[job.id]?.cancel()
        tasks[job.id] = Task { [weak self] in
            guard let self else { return }
            if let source = job.sourceURLString, !source.isEmpty {
                await self.processURL(job)
            } else if job.sourceText != nil {
                await self.processText(job, countUsage: true)
            } else if !job.scratchImageFilenames.isEmpty {
                await self.processImages(job)
            } else {
                self.fail(job, error: .unreadablePage)
            }
            self.tasks[job.id] = nil
        }
    }

    private func processURL(_ job: ImportJob) async {
        job.status = .processing
        job.errorTitle = nil
        job.errorMessage = nil
        job.method = .linkOnly
        job.markUpdated()
        try? store.saveContext()

        guard let rawURL = job.sourceURLString, let url = URL(string: rawURL) else {
            fail(job, error: .invalidInput(.invalidURL))
            return
        }
        let sourceType = job.sourceType

        switch sourceType {
        case .instagram, .facebook:
            await finishLinkOnly(job, url: url, sourceType: sourceType, metadata: nil)
            return
        case .youtube, .tiktok:
            let metadata = await SocialLinkMetadataService.metadata(for: url, sourceType: sourceType)
            await finishSocialLink(job, url: url, sourceType: sourceType, metadata: metadata)
            return
        case .pinterest:
            do {
                let extraction = try await extractPage(url: url, sourceType: sourceType)
                await applyExtraction(extraction, to: job, fallbackURL: url)
            } catch {
                let failure = mappedFailure(error)
                if failure.allowsLinkSave {
                    await finishLinkOnly(job, url: url, sourceType: sourceType, metadata: nil)
                } else {
                    fail(job, error: failure)
                }
            }
            return
        default:
            do {
                let extraction = try await extractPage(url: url, sourceType: sourceType)
                await applyExtraction(extraction, to: job, fallbackURL: url)
            } catch {
                fail(job, error: mappedFailure(error))
            }
        }
    }

    private func finishSocialLink(
        _ job: ImportJob,
        url: URL,
        sourceType: RecipeSourceType,
        metadata: SocialLinkMetadata?
    ) async {
        if let sharedText = job.sourceText, !sharedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let parsed = await Task.detached(priority: .userInitiated) {
                TextRecipeParser.parse(
                    sharedText,
                    sourceType: sourceType,
                    sourceURL: url,
                    sourceTitle: metadata?.title ?? "",
                    method: .textHeuristics
                )
            }.value
            if !parsed.draft.ingredients.isEmpty || !parsed.draft.instructions.isEmpty {
                var draft = parsed.draft
                draft.title = draft.title.isEmpty ? (metadata?.title ?? sourceType.displayName + " recipe") : draft.title
                draft.author = draft.author.isEmpty ? (metadata?.author ?? "") : draft.author
                draft.warnings.append("This recipe was built from text shared from \(sourceType.displayName). Check it against the original.")
                applyDraft(draft, to: job)
                return
            }
        }
        await finishLinkOnly(job, url: url, sourceType: sourceType, metadata: metadata)
    }

    private func finishLinkOnly(
        _ job: ImportJob,
        url: URL,
        sourceType: RecipeSourceType,
        metadata: SocialLinkMetadata?
    ) async {
        job.status = .linkSaved
        job.method = .linkOnly
        job.drafts = []
        job.selectedDraftIndex = 0
        job.displayTitle = metadata?.title.isEmpty == false
            ? metadata!.title
            : "\(sourceType.displayName) link"
        job.errorTitle = nil
        job.errorMessage = nil
        job.retryEligible = false
        job.markUpdated()
        try? store.saveContext()
        _ = url
    }

    private func extractPage(url: URL, sourceType: RecipeSourceType) async throws -> PageExtraction {
        let fetcher = self.fetcher
        return try await Task.detached(priority: .userInitiated) {
            try await WebsiteRecipeExtractor.extract(url: url, sourceType: sourceType, fetcher: fetcher)
        }.value
    }

    private func applyExtraction(_ extraction: PageExtraction, to job: ImportJob, fallbackURL: URL) async {
        guard !extraction.drafts.isEmpty else {
            job.displayTitle = extraction.pageTitle
            job.status = .linkSaved
            job.method = extraction.method
            job.markUpdated()
            try? store.saveContext()
            return
        }
        var drafts = extraction.drafts
        if drafts.count > 1 {
            for index in drafts.indices {
                drafts[index].warnings.append("This page contains multiple recipes. Confirm this is the recipe you meant.")
            }
        }
        job.drafts = drafts
        job.selectedDraftIndex = 0
        job.method = extraction.method
        job.displayTitle = drafts.first?.displayTitle ?? extraction.pageTitle
        job.errorTitle = nil
        job.errorMessage = nil
        job.retryEligible = false
        job.status = drafts.first?.hasCoreContent == true ? .extracted : .needsReview
        job.markUpdated()
        recordUsageIfNeeded(job)
        try? store.saveContext()
    }

    private func processText(_ job: ImportJob, countUsage: Bool) async {
        guard let text = job.sourceText else {
            fail(job, error: .invalidInput(.empty))
            return
        }
        job.status = .processing
        job.markUpdated()
        try? store.saveContext()
        let sourceType = job.sourceType
        let sourceURL = job.sourceURLString.flatMap(URL.init(string:))
        let sourceTitle = job.displayTitle
        let method: ExtractionMethod = sourceType.isSocial ? .textHeuristics : .textHeuristics
        let parsed = await Task.detached(priority: .userInitiated) {
            TextRecipeParser.parse(
                text,
                sourceType: sourceType,
                sourceURL: sourceURL,
                sourceTitle: sourceTitle == "Pasted recipe" ? "" : sourceTitle,
                method: method
            )
        }.value
        applyDraft(parsed.draft, to: job)
        if countUsage { recordUsageIfNeeded(job) }
    }

    private func applyDraft(_ draft: RecipeDraft, to job: ImportJob) {
        job.drafts = [draft]
        job.selectedDraftIndex = 0
        job.displayTitle = draft.displayTitle
        job.method = draft.extractionMethod
        job.status = draft.hasCoreContent ? .extracted : .needsReview
        job.errorTitle = nil
        job.errorMessage = nil
        job.retryEligible = false
        job.markUpdated()
        try? store.saveContext()
    }

    private func processImages(_ job: ImportJob) async {
        job.status = .processing
        job.displayTitle = "Reading screenshot"
        job.markUpdated()
        try? store.saveContext()

        let filenames = job.scratchImageFilenames
        let uiImages = await Task.detached(priority: .userInitiated) {
            filenames.compactMap { filename -> UIImage? in
                guard let data = ImageStore.shared.scratchImageData(named: filename) else { return nil }
                return UIImage(data: data)
            }
        }.value
        guard !uiImages.isEmpty else {
            fail(job, error: .imageUnavailable)
            return
        }

        do {
            let pages = try await ocr.recognizeText(in: uiImages)
            let text = OCRService.combinedText(from: pages)
            let sourceType: RecipeSourceType = job.sourceType == .photo ? .photo : .screenshot
            let parsed = await Task.detached(priority: .userInitiated) {
                TextRecipeParser.parse(
                    text,
                    sourceType: sourceType,
                    sourceURL: job.sourceURLString.flatMap(URL.init(string:)),
                    method: .ocrHeuristics
                )
            }.value
            var draft = parsed.draft
            draft.warnings.insert("Recognized \(pages.count) image\(pages.count == 1 ? "" : "s") on this device. Compare the text with the original before saving.", at: 0)
            job.displayTitle = draft.displayTitle
            applyDraft(draft, to: job)
            recordUsageIfNeeded(job)
        } catch let error as OCRServiceError {
            switch error {
            case .noText:
                fail(job, error: .ocrFailed)
            default:
                fail(job, error: .imageUnavailable)
            }
        } catch is CancellationError {
            fail(job, error: .cancelled)
        } catch {
            fail(job, error: .ocrFailed)
        }
    }

    private func fail(_ job: ImportJob, error: ImportFailure) {
        job.status = .failed
        job.errorTitle = error.title
        job.errorMessage = error.message
        job.retryEligible = error.retryEligible
        job.markUpdated()
        try? store.saveContext()
    }

    private func ensureImportAllowance() throws {
        guard usage.canStartAutomaticImport(isPremium: subscriptions.isPremium) else {
            throw ImportFailure.importLimitReached
        }
    }

    private func recordUsageIfNeeded(_ job: ImportJob) {
        guard !job.didCountUsage else { return }
        job.didCountUsage = true
        usage.recordAutomaticImport(isPremium: subscriptions.isPremium)
    }

    private func mappedFailure(_ error: Error) -> ImportFailure {
        if let failure = error as? ImportFailure { return failure }
        if error is CancellationError { return .cancelled }
        if let ocrError = error as? OCRServiceError {
            return ocrError == .noText ? .ocrFailed : .imageUnavailable
        }
        return .unreadablePage
    }
}
