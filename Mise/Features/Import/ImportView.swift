import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct ImportView: View {
    @Environment(AppDependencies.self) private var app
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \ImportJob.createdAt, order: .reverse) private var jobs: [ImportJob]

    private enum ImportMode: String, CaseIterable, Identifiable {
        case link
        case text
        case photos

        var id: String { rawValue }

        var title: String {
            switch self {
            case .link: return "Link"
            case .text: return "Text"
            case .photos: return "Photos"
            }
        }
    }

    @State private var mode: ImportMode = .link
    @State private var linkText = ""
    @State private var recipeText = ""
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var selectedImages: [UIImage] = []
    @State private var isLoadingPhotos = false

    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var reviewJob: ImportJob?
    @State private var showManualEditor = false
    @State private var showManualFlow = false
    @State private var paywallReason: PaywallReason?
    @State private var jobToDelete: ImportJob?
    @State private var showDeleteConfirmation = false
    @State private var didSaveFromReview = false
    @State private var didSaveManual = false
    @State private var showLimitations = false

    private var recentJobs: [ImportJob] {
        Array(jobs.prefix(8))
    }

    private var canImportMore: Bool {
        app.usage.canStartAutomaticImport(isPremium: app.subscriptions.isPremium)
    }

    private var validatedLink: URL? {
        if case .success(let url) = SourceDetector.validatedURL(from: linkText) {
            return url
        }
        return nil
    }

    private var detectedSourceType: RecipeSourceType? {
        validatedLink.map(SourceDetector.classify)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    intro
                    allowance
                    modePicker
                    switch mode {
                    case .link:
                        linkForm
                    case .text:
                        textForm
                    case .photos:
                        photoForm
                    }
                    manualCard
                    recentImports
                    limitations
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 36)
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(PageBackground())
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Add a recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(MiseTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .sheet(item: $reviewJob, onDismiss: {
            if didSaveFromReview {
                didSaveFromReview = false
                dismiss()
            }
        }) { job in
            ImportReviewView(job: job) { recipe in
                didSaveFromReview = true
                router.showToast("Saved “\(recipe.title)”")
            }
            .environment(app)
            .environment(router)
            .modelContainer(app.container)
        }
        .sheet(isPresented: $showManualEditor, onDismiss: {
            if didSaveManual {
                didSaveManual = false
                dismiss()
            }
        }) {
            RecipeEditorView { recipe in
                didSaveManual = true
                router.showToast("Saved “\(recipe.title)”")
            }
            .environment(app)
            .environment(router)
            .modelContainer(app.container)
        }
        .sheet(item: $paywallReason) { reason in
            PaywallView(reason: reason)
                .environment(app)
                .environment(router)
                .modelContainer(app.container)
        }
        .alert("Couldn’t import", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .alert("Delete import?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { jobToDelete = nil }
            Button("Delete", role: .destructive) {
                if let jobToDelete {
                    app.imports.delete(jobToDelete)
                }
                jobToDelete = nil
            }
        } message: {
            Text("This removes the import attempt and any temporary screenshots. Recipes you already saved are not affected.")
        }
        .task {
            app.usage.refreshForCurrentMonth()
        }
        .onChange(of: photoItems) { _, items in
            loadPhotos(items)
        }
    }

    // MARK: - Intro

    private var intro: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Bring in a recipe")
                .font(.system(.largeTitle, design: .serif, weight: .semibold))
                .foregroundStyle(MiseTheme.ink)
                .accessibilityAddTraits(.isHeader)
            Text("Choose what you have. You’ll review everything before it reaches your library.")
                .font(.body)
                .foregroundStyle(MiseTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var allowance: some View {
        HStack(spacing: 11) {
            Image(systemName: canImportMore ? "sparkles" : "lock")
                .font(.caption.weight(.semibold))
                .foregroundStyle(canImportMore ? MiseTheme.sage : MiseTheme.accent)
                .frame(width: 32, height: 32)
                .background(Circle().fill((canImportMore ? MiseTheme.sage : MiseTheme.accent).opacity(0.1)))
            VStack(alignment: .leading, spacing: 2) {
                if app.subscriptions.isPremium {
                    Text("Mise Premium is active")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MiseTheme.ink)
                    Text("Unlimited automatic imports and collections.")
                        .font(.caption2)
                        .foregroundStyle(MiseTheme.secondaryInk)
                } else if canImportMore {
                    Text("\(app.usage.remainingFreeImports) of \(FreeTier.automaticImportsPerMonth) automatic imports left")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MiseTheme.ink)
                    Text("Manual recipes are always unlimited. Resets monthly.")
                        .font(.caption2)
                        .foregroundStyle(MiseTheme.secondaryInk)
                } else {
                    Text("This month’s free imports are used")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MiseTheme.ink)
                    Text("Manual entry is still unlimited. Premium removes the import cap.")
                        .font(.caption2)
                        .foregroundStyle(MiseTheme.secondaryInk)
                }
            }
            Spacer(minLength: 0)
            if !app.subscriptions.isPremium {
                Button {
                    paywallReason = .importLimit
                } label: {
                    Text("Premium")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MiseTheme.accent)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(MiseTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(MiseTheme.line, lineWidth: 1)
        )
    }

    private var modePicker: some View {
        Picker("Import method", selection: $mode) {
            ForEach(ImportMode.allCases) { option in
                Text(option.title).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("importModePicker")
    }

    // MARK: - Link

    private var linkForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 7) {
                FieldLabel(text: "Recipe link")
                HStack(spacing: 8) {
                    ZStack(alignment: .leading) {
                        if linkText.isEmpty {
                            Text("https://example.com/recipe")
                                .foregroundStyle(MiseTheme.secondaryInk.opacity(0.55))
                                .lineLimit(1)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                        TextField("", text: $linkText)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .foregroundStyle(MiseTheme.ink)
                            .accessibilityLabel("Recipe link")
                            .accessibilityIdentifier("importLinkField")
                    }
                    Button {
                        if let pasted = UIPasteboard.general.string {
                            linkText = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    } label: {
                        Text("Paste")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(MiseTheme.accent)
                    }
                    .accessibilityLabel("Paste link")
                }
                .padding(.horizontal, 13)
                .frame(minHeight: 50)
                .background(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(MiseTheme.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(MiseTheme.line, lineWidth: 1)
                )
            }

            if !linkText.isEmpty {
                linkPreview
            }

            Button {
                startLinkImport()
            } label: {
                HStack(spacing: 8) {
                    if isWorking {
                        ProgressView().tint(MiseTheme.background)
                    } else {
                        Image(systemName: "arrow.down.to.line.compact")
                    }
                    Text(isWorking ? "Reading the page…" : "Import link")
                }
            }
            .buttonStyle(PrimaryButtonStyle(fill: canImportMore ? MiseTheme.ink : MiseTheme.accent))
            .disabled(validatedLink == nil || isWorking)
            .opacity(validatedLink == nil ? 0.55 : 1)
            .accessibilityIdentifier("startLinkImportButton")

            Text("Mise reads public pages only. It never signs in, bypasses a paywall or CAPTCHA, or scrapes private content.")
                .font(.caption2)
                .foregroundStyle(MiseTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var linkPreview: some View {
        if let url = validatedLink, let sourceType = detectedSourceType {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: sourceType.symbolName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MiseTheme.sage)
                    Text(sourceType.isSocial ? "\(sourceType.displayName) link detected" : sourceType == .pinterest ? "Pinterest link detected" : "Recipe webpage detected")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MiseTheme.ink)
                    Spacer()
                    Text(url.host ?? "")
                        .font(.caption2)
                        .foregroundStyle(MiseTheme.secondaryInk)
                        .lineLimit(1)
                }
                Text(sourceType.isSocial
                     ? "\(sourceType.displayName) often keeps the recipe inside the video or caption. Mise will save the link and use any public metadata it can. For the full recipe, paste the caption in the Text tab or choose a screenshot."
                     : "Mise will look for published recipe data first, then readable page text. You’ll review the result before saving.")
                    .font(.caption)
                    .foregroundStyle(MiseTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(MiseTheme.sage.opacity(0.07))
            )
        } else {
            InlineNotice(
                style: .warning,
                message: importInputMessage,
                title: "That link needs a check"
            )
        }
    }

    private var importInputMessage: String {
        if case .failure(let error) = SourceDetector.validatedURL(from: linkText) {
            return [error.errorDescription, error.recoverySuggestion].compactMap { $0 }.joined(separator: " ")
        }
        return "Paste an http or https link to a public recipe page."
    }

    // MARK: - Text

    private var textForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 7) {
                FieldLabel(text: "Recipe text")
                ZStack(alignment: .topLeading) {
                    if recipeText.isEmpty {
                        Text("Paste the recipe, a caption, or notes from a video. Include ingredients and steps if you have them.")
                            .font(.body)
                            .foregroundStyle(MiseTheme.secondaryInk.opacity(0.6))
                            .padding(.top, 13)
                            .padding(.leading, 17)
                            .padding(.trailing, 14)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $recipeText)
                        .font(.body)
                        .frame(minHeight: 190)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .accessibilityIdentifier("importTextEditor")
                }
                .background(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(MiseTheme.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(MiseTheme.line, lineWidth: 1)
                )
            }

            HStack {
                Button {
                    if let pasted = UIPasteboard.general.string {
                        recipeText = pasted
                    }
                } label: {
                    Label("Paste from clipboard", systemImage: "doc.on.clipboard")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MiseTheme.accent)
                }
                Spacer()
                if !recipeText.isEmpty {
                    Button {
                        recipeText = ""
                    } label: {
                        Text("Clear")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(MiseTheme.secondaryInk)
                    }
                }
                Text("\(recipeText.count) characters")
                    .font(.caption2)
                    .foregroundStyle(MiseTheme.secondaryInk)
            }

            Button {
                startTextImport()
            } label: {
                HStack(spacing: 8) {
                    if isWorking {
                        ProgressView().tint(MiseTheme.background)
                    } else {
                        Image(systemName: "text.alignleft")
                    }
                    Text(isWorking ? "Reading the text…" : "Extract recipe")
                }
            }
            .buttonStyle(PrimaryButtonStyle(fill: MiseTheme.ink))
            .disabled(recipeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isWorking)
            .opacity(recipeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.55 : 1)
            .accessibilityIdentifier("startTextImportButton")

            Text("Text is read on this iPhone into a draft. Mise doesn’t upload it, and you review the result before saving.")
                .font(.caption2)
                .foregroundStyle(MiseTheme.secondaryInk)
        }
    }

    // MARK: - Photos

    private var photoForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                FieldLabel(text: "Screenshots or photos")
                PhotosPicker(
                    selection: $photoItems,
                    maxSelectionCount: 4,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    HStack(spacing: 10) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 17, weight: .semibold))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(photoItems.isEmpty ? "Choose screenshots" : "Change selection")
                                .font(.subheadline.weight(.semibold))
                            Text("Up to 4 images")
                                .font(.caption2)
                                .foregroundStyle(MiseTheme.secondaryInk)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(MiseTheme.secondaryInk)
                    }
                    .foregroundStyle(MiseTheme.ink)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(MiseTheme.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .stroke(MiseTheme.line, lineWidth: 1)
                    )
                }
                .accessibilityIdentifier("chooseScreenshotsButton")

                if isLoadingPhotos {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Preparing images…")
                            .font(.caption)
                            .foregroundStyle(MiseTheme.secondaryInk)
                    }
                } else if !selectedImages.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 9) {
                            ForEach(Array(selectedImages.enumerated()), id: \.offset) { _, image in
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 92, height: 128)
                                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                            }
                        }
                    }
                    .scrollClipDisabled()
                }
            }

            Button {
                startPhotoImport()
            } label: {
                HStack(spacing: 8) {
                    if isWorking {
                        ProgressView().tint(MiseTheme.background)
                    } else {
                        Image(systemName: "text.viewfinder")
                    }
                    Text(isWorking ? "Reading on device…" : "Read screenshots")
                }
            }
            .buttonStyle(PrimaryButtonStyle(fill: MiseTheme.ink))
            .disabled(selectedImages.isEmpty || isWorking || isLoadingPhotos)
            .opacity(selectedImages.isEmpty ? 0.55 : 1)
            .accessibilityIdentifier("startOCRImportButton")

            InlineNotice(
                style: .info,
                message: "Text recognition runs on this iPhone. Recipe screenshots that are mostly image with little text won’t work — in that case, type or paste the recipe instead."
            )
        }
    }

    // MARK: - Manual

    private var manualCard: some View {
        Button {
            showManualEditor = true
        } label: {
            HStack(spacing: 13) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(MiseTheme.accent)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(MiseTheme.accent.opacity(0.1)))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Write it yourself")
                        .font(.system(.headline, design: .serif, weight: .semibold))
                        .foregroundStyle(MiseTheme.ink)
                    Text("Always free, always yours. No import needed.")
                        .font(.caption)
                        .foregroundStyle(MiseTheme.secondaryInk)
                }
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(MiseTheme.secondaryInk)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(MiseTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(MiseTheme.line, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("manualRecipeButton")
    }

    // MARK: - Recent imports

    @ViewBuilder
    private var recentImports: some View {
        if !recentJobs.isEmpty {
            VStack(alignment: .leading, spacing: 11) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Recent imports")
                        .font(.system(.title3, design: .serif, weight: .semibold))
                        .foregroundStyle(MiseTheme.ink)
                    Spacer()
                    if recentJobs.contains(where: { $0.status == .completed || $0.status == .failed }) {
                        Button("Clear finished") {
                            for job in jobs where job.status == .completed || job.status == .failed {
                                app.imports.delete(job)
                            }
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MiseTheme.secondaryInk)
                    }
                }
                VStack(spacing: 9) {
                    ForEach(recentJobs) { job in
                        jobCard(job)
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    private func jobCard(_ job: ImportJob) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: job.sourceType.symbolName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MiseTheme.secondaryInk)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(MiseTheme.raisedSurface))
                VStack(alignment: .leading, spacing: 3) {
                    Text(job.displayTitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(MiseTheme.ink)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        StatusBadge(status: job.status)
                        Text(job.updatedAt.formatted(.relative(presentation: .named)))
                            .font(.caption2)
                            .foregroundStyle(MiseTheme.secondaryInk)
                    }
                }
                Spacer(minLength: 0)
                Menu {
                    if job.status != .completed {
                        Button {
                            reviewJob = job
                        } label: {
                            Label(job.status == .failed ? "Add details" : "Review import", systemImage: "pencil")
                        }
                    }
                    if job.status == .failed && job.retryEligible {
                        Button {
                            app.imports.retry(job)
                        } label: {
                            Label("Try again", systemImage: "arrow.clockwise")
                        }
                    }
                    if job.status == .processing || job.status == .queued {
                        Button(role: .destructive) {
                            app.imports.cancel(job)
                        } label: {
                            Label("Cancel import", systemImage: "xmark")
                        }
                    }
                    if job.status == .completed, let id = job.completedRecipeID, let recipe = app.store.recipe(id: id) {
                        Button {
                            router.showImport = false
                            router.selectedTab = .library
                            _ = recipe
                        } label: {
                            Label("Find in library", systemImage: "books.vertical")
                        }
                    }
                    Divider()
                    Button(role: .destructive) {
                        jobToDelete = job
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete import", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(MiseTheme.secondaryInk)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Import options")
            }

            if job.status == .processing || job.status == .queued {
                ProgressView()
                    .tint(MiseTheme.sage)
            }

            if let message = job.errorMessage, job.status == .failed {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(MiseTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    if job.retryEligible {
                        Button("Try again") {
                            app.imports.retry(job)
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MiseTheme.accent)
                    }
                    Button("Add details") {
                        reviewJob = job
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MiseTheme.ink)
                }
            } else if job.status == .linkSaved {
                Text("The link is saved. Add the details now, or keep it as a reference.")
                    .font(.caption)
                    .foregroundStyle(MiseTheme.secondaryInk)
                HStack(spacing: 12) {
                    Button("Add details") {
                        reviewJob = job
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MiseTheme.accent)
                    Button("Save link to library") {
                        saveLink(job)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MiseTheme.ink)
                }
            } else if job.status == .needsReview || job.status == .extracted {
                Button {
                    reviewJob = job
                } label: {
                    Text("Review recipe")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MiseTheme.accent)
                }
            }
        }
        .padding(13)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(MiseTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(MiseTheme.line, lineWidth: 1)
        )
    }

    // MARK: - Limitations

    private var limitations: some View {
        DisclosureGroup(isExpanded: $showLimitations) {
            VStack(alignment: .leading, spacing: 9) {
                limitationRow("Recipe websites", "Best results when a site publishes structured recipe data. Otherwise Mise reads visible page text and asks you to review it.")
                limitationRow("Instagram, TikTok, Facebook", "Mise does not sign in, scrape private posts, or download video. Save the link, then paste the caption or use a screenshot.")
                limitationRow("YouTube and Pinterest", "Public metadata may be available, but the full recipe often lives in the description, video, or linked page. Add what’s missing yourself.")
                limitationRow("Paywalls, logins, CAPTCHAs", "Mise never bypasses access controls. Save the link and add the recipe from text you have access to.")
                limitationRow("Screenshots", "On-device text recognition can misread fractions and small type. Check the draft against the original.")
            }
            .padding(.top, 10)
        } label: {
            Text("What Mise can and can’t import")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(MiseTheme.ink)
        }
        .padding(15)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(MiseTheme.raisedSurface)
        )
        .tint(MiseTheme.sage)
    }

    private func limitationRow(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(MiseTheme.ink)
            Text(detail)
                .font(.caption)
                .foregroundStyle(MiseTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Actions

    private func startLinkImport() {
        guard canImportMore else {
            paywallReason = .importLimit
            Haptics.warning()
            return
        }
        guard validatedLink != nil else { return }
        isWorking = true
        errorMessage = nil
        do {
            let job = try app.imports.startURLImport(rawInput: linkText)
            watch(job)
        } catch {
            isWorking = false
            errorMessage = (error as? ImportFailure)?.message ?? "Mise couldn’t start that import. Check the link and try again."
        }
    }

    private func startTextImport() {
        guard canImportMore else {
            paywallReason = .importLimit
            Haptics.warning()
            return
        }
        let text = recipeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isWorking = true
        errorMessage = nil
        Task {
            do {
                let job = try await app.imports.startTextImport(text: text)
                watch(job)
            } catch {
                isWorking = false
                errorMessage = (error as? ImportFailure)?.message ?? "Mise couldn’t read that text. Try again or write the recipe yourself."
            }
        }
    }

    private func startPhotoImport() {
        guard canImportMore else {
            paywallReason = .importLimit
            Haptics.warning()
            return
        }
        guard !selectedImages.isEmpty else { return }
        isWorking = true
        errorMessage = nil
        Task {
            do {
                let job = try await app.imports.startImageImport(images: selectedImages)
                watch(job)
            } catch {
                isWorking = false
                errorMessage = (error as? ImportFailure)?.message ?? "Mise couldn’t open those images. Try choosing them again."
            }
        }
    }

    private func watch(_ job: ImportJob) {
        Task {
            for _ in 0..<240 {
                if job.status == .extracted || job.status == .needsReview || job.status == .linkSaved || job.status == .failed || job.status == .completed {
                    break
                }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
            isWorking = false
            switch job.status {
            case .extracted, .needsReview, .linkSaved:
                Haptics.success()
                reviewJob = job
            case .failed:
                Haptics.warning()
                errorMessage = job.errorMessage ?? "Mise couldn’t import that page. You can add the details yourself."
            default:
                break
            }
        }
    }

    private func saveLink(_ job: ImportJob) {
        Task {
            do {
                let recipe = try await app.imports.saveLinkPlaceholder(for: job)
                router.showToast("Saved “\(recipe.title)”")
            } catch {
                errorMessage = "Mise couldn’t save that link. Please try again."
            }
        }
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else {
            selectedImages = []
            return
        }
        isLoadingPhotos = true
        Task {
            var images: [UIImage] = []
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    images.append(image)
                }
            }
            selectedImages = images
            isLoadingPhotos = false
            if images.isEmpty {
                errorMessage = "Those images couldn’t be opened. Try choosing them again from Photos."
            }
        }
    }
}

// MARK: - Review wrapper

struct ImportReviewView: View {
    @Environment(AppDependencies.self) private var app
    @Environment(AppRouter.self) private var router

    let job: ImportJob
    var onSaved: (Recipe) -> Void = { _ in }

    var body: some View {
        RecipeEditorView(job: job) { recipe in
            onSaved(recipe)
        }
        .environment(app)
        .environment(router)
    }
}
