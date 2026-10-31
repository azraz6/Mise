import PhotosUI
import SwiftData
import SwiftUI

enum RecipeEditorMode {
    case manual
    case edit(Recipe)
    case review(ImportJob)
}

struct RecipeEditorView: View {
    @Environment(AppDependencies.self) private var app
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    let mode: RecipeEditorMode
    let onSaved: (Recipe) -> Void

    @State private var draft: RecipeDraft
    @State private var initialDraft: RecipeDraft
    @State private var tagsText: String
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var duplicates: [DuplicateCandidate] = []
    @State private var showDuplicateWarning = false
    @State private var showDiscardConfirmation = false
    @State private var draftIndex = 0
    @State private var hasAcceptedDuplicate = false
    @FocusState private var focusedField: EditorField?

    private enum EditorField: Hashable {
        case title
        case summary
        case tags
        case notes
    }

    init(recipe: Recipe, onSaved: @escaping (Recipe) -> Void = { _ in }) {
        self.mode = .edit(recipe)
        self.onSaved = onSaved
        let value = recipe.toDraft()
        _draft = State(initialValue: value)
        _initialDraft = State(initialValue: value)
        _tagsText = State(initialValue: value.tags.joined(separator: ", "))
    }

    init(job: ImportJob, onSaved: @escaping (Recipe) -> Void = { _ in }) {
        self.mode = .review(job)
        self.onSaved = onSaved
        let value: RecipeDraft
        if let selected = job.selectedDraft {
            value = selected
        } else {
            value = RecipeDraft(
                title: job.displayTitle,
                sourceTitle: job.displayTitle,
                sourceURLString: job.sourceURLString,
                sourceType: job.sourceType,
                extractionMethod: job.method,
                confidence: .unverified,
                warnings: ["Only the source link was saved. Add ingredients and steps before cooking."]
            )
        }
        _draft = State(initialValue: value)
        _initialDraft = State(initialValue: value)
        _tagsText = State(initialValue: value.tags.joined(separator: ", "))
    }

    init(onSaved: @escaping (Recipe) -> Void = { _ in }) {
        self.mode = .manual
        self.onSaved = onSaved
        let value = RecipeDraft.manual()
        _draft = State(initialValue: value)
        _initialDraft = State(initialValue: value)
        _tagsText = State(initialValue: "")
    }

    private var reviewJob: ImportJob? {
        if case .review(let job) = mode { return job }
        return nil
    }

    private var editingRecipe: Recipe? {
        if case .edit(let recipe) = mode { return recipe }
        return nil
    }

    private var screenTitle: String {
        switch mode {
        case .manual: return "New recipe"
        case .edit: return "Edit recipe"
        case .review: return "Review import"
        }
    }

    private var canSave: Bool {
        !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && draft.ingredients.contains { !$0.originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            && draft.instructions.contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            && !isSaving
    }

    private var canSaveLinkOnly: Bool {
        guard let job = reviewJob else { return false }
        return job.drafts.isEmpty || job.method == .linkOnly || job.status == .linkSaved
    }

    private var missingFields: [String] {
        RecipeValidator.missingFields(for: draft)
    }

    private var hasAnyDraftContent: Bool {
        !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !draft.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || draft.ingredients.contains { !$0.originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            || draft.instructions.contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private var shouldShowMissingFields: Bool {
        hasAnyDraftContent
    }

    private var coverHeight: CGFloat {
        if case .manual = mode { return 150 }
        return 200
    }

    private var displayWarnings: [String] {
        let warnings = draft.allWarnings
        return Array(NSOrderedSet(array: warnings).compactMap { $0 as? String })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let job = reviewJob {
                        reviewBanner(job)
                    }
                    coverEditor
                    if !missingFields.isEmpty && shouldShowMissingFields {
                        InlineNotice(
                            style: .info,
                            message: "Add a title, at least one ingredient, and one step to save this recipe. \(missingFields.joined(separator: ", ")) still needed.",
                            title: "A little more to go"
                        )
                    }
                    basicsSection
                    timingSection
                    ingredientsSection
                    instructionsSection
                    notesSection
                    if !displayWarnings.isEmpty {
                        warningsSection
                    }
                    sourceSection
                    if canSaveLinkOnly {
                        saveLinkSection
                    }
                    if isSaving {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Saving to your library…")
                                .font(.subheadline)
                                .foregroundStyle(MiseTheme.secondaryInk)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 36)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .background(PageBackground())
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(screenTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(MiseTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if isDirty {
                            showDiscardConfirmation = true
                        } else {
                            dismiss()
                        }
                    }
                    .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        attemptSave()
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save").fontWeight(.semibold)
                        }
                    }
                    .disabled(!canSave)
                    .accessibilityIdentifier("saveRecipeButton")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        focusedField = nil
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
            }
        }
        .interactiveDismissDisabled(isSaving)
        .onChange(of: selectedPhotoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    selectedImage = image
                    draft.coverImageRemoteURL = nil
                    Haptics.tap()
                }
            }
        }
        .alert("Possible duplicate", isPresented: $showDuplicateWarning) {
            Button("Cancel", role: .cancel) { hasAcceptedDuplicate = false }
            Button("Save anyway") {
                hasAcceptedDuplicate = true
                performSave()
            }
        } message: {
            let names = duplicates.prefix(3).map { "“\($0.title)”" }.joined(separator: ", ")
            Text("This looks similar to \(names) already in your library. Save it anyway, or cancel to check first.")
        }
        .alert("Couldn’t save", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .alert("Discard changes?", isPresented: $showDiscardConfirmation) {
            Button("Keep editing", role: .cancel) {}
            Button("Discard", role: .destructive) { dismiss() }
        } message: {
            Text("Your edits to this recipe haven’t been saved.")
        }
    }

    private var isDirty: Bool {
        draft != initialDraft || selectedImage != nil
    }

    // MARK: - Review banner

    private func reviewBanner(_ job: ImportJob) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label(job.sourceType.displayName, systemImage: job.sourceType.symbolName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MiseTheme.ink)
                Spacer()
                Text(draft.confidence.displayName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(MiseTheme.warning)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(MiseTheme.warning.opacity(0.1)))
            }
            Text(reviewMessage(job))
                .font(.caption)
                .foregroundStyle(MiseTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)

            if job.drafts.count > 1 {
                Menu {
                    ForEach(Array(job.drafts.enumerated()), id: \.offset) { index, candidate in
                        Button {
                            switchDraft(index, job: job)
                        } label: {
                            if index == draftIndex {
                                Label(candidate.displayTitle, systemImage: "checkmark")
                            } else {
                                Text(candidate.displayTitle)
                            }
                        }
                    }
                } label: {
                    HStack {
                        Text("Recipe \(draftIndex + 1) of \(job.drafts.count)")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("Choose another")
                            .font(.caption)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2.weight(.bold))
                    }
                    .foregroundStyle(MiseTheme.ink)
                    .padding(11)
                    .background(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(MiseTheme.raisedSurface)
                    )
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(MiseTheme.warning.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(MiseTheme.warning.opacity(0.22), lineWidth: 1)
        )
    }

    private func reviewMessage(_ job: ImportJob) -> String {
        if job.sourceType.isSocial {
            return "\(job.sourceType.displayName) often hides recipe details from other apps. Mise only uses what you shared or what the public page offered. Check everything before saving."
        }
        switch draft.extractionMethod {
        case .jsonLD:
            return "The page published structured recipe data. Review the details and make any edits before saving."
        case .pageHeuristics:
            return "This came from the visible page text, not verified recipe data. Check quantities and steps carefully."
        case .textHeuristics, .ocrHeuristics:
            return "This draft came from on-device text recognition and heuristics. Fractions, units, and small print can be misread — compare with the original."
        case .linkOnly:
            return "Only the link was saved. Add the ingredients and steps, or save the link for later."
        case .oEmbed, .manual:
            return "Review the details before saving them to your library."
        }
    }

    private func switchDraft(_ index: Int, job: ImportJob) {
        guard job.drafts.indices.contains(index) else { return }
        draftIndex = index
        app.imports.selectDraft(index, in: job)
        if let selected = job.selectedDraft {
            draft = selected
            initialDraft = selected
            tagsText = selected.tags.joined(separator: ", ")
            selectedImage = nil
        }
    }

    // MARK: - Cover

    private var coverEditor: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let selectedImage {
                    Image(uiImage: selectedImage)
                        .resizable()
                        .scaledToFill()
                } else if let raw = draft.coverImageRemoteURL, let url = URL(string: raw) {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            placeholderCover
                        }
                    }
                } else {
                    RecipeCoverImage(
                        filename: draft.coverImageFilename,
                        assetName: draft.coverAssetName,
                        cornerRadius: 18,
                        symbolSize: 30
                    )
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: coverHeight)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            PhotosPicker(selection: $selectedPhotoItem, matching: .images, photoLibrary: .shared()) {
                Label(selectedImage == nil ? "Add photo" : "Change photo", systemImage: "photo")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MiseTheme.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(.regularMaterial))
            }
            .padding(12)
            .accessibilityLabel("Choose cover photo")
        }
    }

    private var placeholderCover: some View {
        ZStack {
            MiseTheme.raisedSurface
            Image(systemName: "fork.knife")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(MiseTheme.sage.opacity(0.55))
        }
    }

    // MARK: - Basics

    private var basicsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            editorField("Title") {
                TextField("What are we cooking?", text: $draft.title, axis: .vertical)
                    .font(.system(.title2, design: .serif, weight: .semibold))
                    .focused($focusedField, equals: .title)
                    .accessibilityIdentifier("recipeTitleField")
            }

            editorField("Summary", optional: true) {
                ZStack(alignment: .topLeading) {
                    if draft.summary.isEmpty {
                        Text("A sentence about why this recipe is worth cooking.")
                            .font(.body)
                            .foregroundStyle(MiseTheme.secondaryInk.opacity(0.65))
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $draft.summary)
                        .font(.body)
                        .frame(minHeight: 72)
                        .scrollContentBackground(.hidden)
                        .focused($focusedField, equals: .summary)
                }
            }

            HStack(alignment: .top, spacing: 12) {
                editorField("Cuisine", optional: true) {
                    TextField("Italian", text: $draft.cuisine)
                }
                editorField("Category", optional: true) {
                    TextField("Dinner", text: $draft.category)
                }
            }

            editorField("Tags", optional: true) {
                TextField("weeknight, vegetarian, make ahead", text: $tagsText)
                    .focused($focusedField, equals: .tags)
                    .textInputAutocapitalization(.never)
            }
        }
    }

    // MARK: - Timing

    private var timingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Time & yield")
                .font(.system(.headline, design: .serif, weight: .semibold))
                .foregroundStyle(MiseTheme.ink)
            HStack(alignment: .top, spacing: 10) {
                EditorNumberField(label: "Prep min", value: $draft.prepMinutes)
                EditorNumberField(label: "Cook min", value: $draft.cookMinutes)
                EditorNumberField(label: "Total min", value: $draft.totalMinutes)
            }
            HStack(alignment: .top, spacing: 10) {
                EditorNumberField(label: "Servings", value: $draft.servings)
                editorField("Serving note", optional: true) {
                    TextField("4 bowls", text: Binding(
                        get: { draft.servingsDescription ?? "" },
                        set: { draft.servingsDescription = $0.isEmpty ? nil : $0 }
                    ))
                }
            }
            Text("Times are in minutes. Leave fields blank if you don’t know them.")
                .font(.caption2)
                .foregroundStyle(MiseTheme.secondaryInk)
        }
        .padding(15)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(MiseTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(MiseTheme.line, lineWidth: 1)
        )
    }

    // MARK: - Ingredients

    private var ingredientsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Ingredients")
                    .font(.system(.title2, design: .serif, weight: .semibold))
                    .foregroundStyle(MiseTheme.ink)
                Spacer()
                Text("One per line")
                    .font(.caption)
                    .foregroundStyle(MiseTheme.secondaryInk)
            }

            VStack(spacing: 8) {
                ForEach(draft.ingredients.indices, id: \.self) { index in
                    let ingredient = $draft.ingredients[index]
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "line.3.horizontal")
                            .font(.caption2)
                            .foregroundStyle(MiseTheme.secondaryInk.opacity(0.55))
                            .padding(.top, 4)
                        TextField("e.g. 2 tbsp olive oil", text: Binding(
                            get: { ingredient.wrappedValue.originalText },
                            set: { newValue in
                                var copy = ingredient.wrappedValue
                                copy.updateText(newValue)
                                ingredient.wrappedValue = copy
                            }
                        ), axis: .vertical)
                        .font(.body)
                        .lineLimit(1...4)
                        .accessibilityIdentifier("ingredientField_\(index)")
                        if draft.ingredients.count > 1 {
                            Button {
                                let id = ingredient.wrappedValue.id
                                draft.ingredients.removeAll { $0.id == id }
                            } label: {
                                Image(systemName: "minus.circle")
                                    .foregroundStyle(MiseTheme.secondaryInk)
                            }
                            .accessibilityLabel("Remove ingredient \(ingredient.wrappedValue.name)")
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(MiseTheme.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(MiseTheme.line, lineWidth: 1)
                    )
                }
            }

            Button {
                draft.ingredients.append(Ingredient(text: "", order: draft.ingredients.count))
                Haptics.tap()
            } label: {
                Label("Add ingredient", systemImage: "plus.circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MiseTheme.accent)
            }
        }
    }

    // MARK: - Instructions

    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Method")
                    .font(.system(.title2, design: .serif, weight: .semibold))
                    .foregroundStyle(MiseTheme.ink)
                Spacer()
                Text("One step per box")
                    .font(.caption)
                    .foregroundStyle(MiseTheme.secondaryInk)
            }

            VStack(spacing: 10) {
                ForEach(draft.instructions.indices, id: \.self) { index in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(index + 1)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(MiseTheme.surface)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(MiseTheme.sage))
                            .padding(.top, 8)
                        TextField("Describe this step", text: $draft.instructions[index].text, axis: .vertical)
                            .font(.body)
                            .lineLimit(2...8)
                            .padding(.vertical, 6)
                            .accessibilityIdentifier("instructionField_\(index)")
                        if draft.instructions.count > 1 {
                            Button {
                                let id = draft.instructions[index].id
                                draft.instructions.removeAll { $0.id == id }
                            } label: {
                                Image(systemName: "minus.circle")
                                    .foregroundStyle(MiseTheme.secondaryInk)
                                    .padding(.top, 6)
                            }
                            .accessibilityLabel("Remove step \(index + 1)")
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(MiseTheme.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(MiseTheme.line, lineWidth: 1)
                    )
                }
            }

            Button {
                draft.instructions.append(Instruction(text: "", order: draft.instructions.count))
                Haptics.tap()
            } label: {
                Label("Add step", systemImage: "plus.circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MiseTheme.accent)
            }
        }
    }

    // MARK: - Notes

    private var notesSection: some View {
        editorField("Notes", optional: true) {
            ZStack(alignment: .topLeading) {
                if draft.notes.isEmpty {
                    Text("Substitutions, timing tips, or what to remember next time.")
                        .font(.body)
                        .foregroundStyle(MiseTheme.secondaryInk.opacity(0.65))
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $draft.notes)
                    .font(.body)
                    .frame(minHeight: 90)
                    .scrollContentBackground(.hidden)
                    .focused($focusedField, equals: .notes)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(MiseTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(MiseTheme.line, lineWidth: 1)
            )
        }
    }

    private var warningsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Worth checking", systemImage: "exclamationmark.triangle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(MiseTheme.warning)
            ForEach(displayWarnings, id: \.self) { warning in
                HStack(alignment: .top, spacing: 7) {
                    Text("·")
                    Text(warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.caption)
                .foregroundStyle(MiseTheme.secondaryInk)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(MiseTheme.warning.opacity(0.07))
        )
    }

    // MARK: - Source

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Source")
                .font(.system(.headline, design: .serif, weight: .semibold))
                .foregroundStyle(MiseTheme.ink)
            HStack(spacing: 8) {
                Label(draft.sourceType.displayName, systemImage: draft.sourceType.symbolName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(MiseTheme.secondaryInk)
                Spacer()
                Text(draft.extractionMethod.displayName)
                    .font(.caption2)
                    .foregroundStyle(MiseTheme.secondaryInk)
            }
            editorField("Source link", optional: true) {
                TextField("https://", text: Binding(
                    get: { draft.sourceURLString ?? "" },
                    set: { draft.sourceURLString = $0.isEmpty ? nil : $0 }
                ))
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            }
            editorField("Credit", optional: true) {
                TextField("Original author or publication", text: $draft.attribution)
            }
        }
        .padding(15)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(MiseTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(MiseTheme.line, lineWidth: 1)
        )
    }

    private var saveLinkSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Not enough to cook yet?")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(MiseTheme.ink)
            Text("You can keep the link in your library and fill in the details later. It won’t count as a second import.")
                .font(.caption)
                .foregroundStyle(MiseTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                saveLinkOnly()
            } label: {
                Label("Save link for later", systemImage: "link")
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(isSaving)
        }
    }

    // MARK: - Shared fields

    private func editorField<Content: View>(
        _ label: String,
        optional: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            FieldLabel(text: label, optional: optional)
            content()
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(MiseTheme.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(MiseTheme.line, lineWidth: 1)
                )
        }
    }

    // MARK: - Saving

    private func attemptSave() {
        guard canSave else { return }
        focusedField = nil
        let prepared = preparedDraft()
        let existing = app.store.allRecipes()
        let candidates = DuplicateDetector.candidates(
            for: prepared,
            excluding: editingRecipe?.id,
            in: existing
        )
        if !candidates.isEmpty && !hasAcceptedDuplicate {
            duplicates = candidates
            showDuplicateWarning = true
            return
        }
        performSave()
    }

    private func preparedDraft() -> RecipeDraft {
        var result = draft
        result.title = result.title.trimmingCharacters(in: .whitespacesAndNewlines)
        result.summary = result.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        result.notes = result.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        result.attribution = result.attribution.trimmingCharacters(in: .whitespacesAndNewlines)
        result.cuisine = result.cuisine.trimmingCharacters(in: .whitespacesAndNewlines)
        result.category = result.category.trimmingCharacters(in: .whitespacesAndNewlines)
        result.tags = tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        result.ingredients = result.ingredients
            .filter { !$0.originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        result.instructions = result.instructions
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .enumerated()
            .map { index, instruction in
                Instruction(
                    id: instruction.id,
                    text: instruction.text.trimmingCharacters(in: .whitespacesAndNewlines),
                    order: index,
                    group: instruction.group
                )
            }
        result.sourceURLString = result.sourceURLString?.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.sourceURLString?.isEmpty == true { result.sourceURLString = nil }

        if result.hasCoreContent {
            result.warnings.removeAll { $0.contains("Only the source link was saved") }
            if result.extractionMethod == .linkOnly {
                result.extractionMethod = .manual
            }
        }
        result.normalizeOrdering()
        return result
    }

    private func performSave() {
        guard !isSaving else { return }
        isSaving = true
        let prepared = preparedDraft()
        let image = selectedImage
        Task {
            do {
                switch mode {
                case .manual:
                    let recipe = try await app.store.save(draft: prepared, image: image)
                    finish(recipe)
                case .edit(let recipe):
                    try await app.store.update(recipe: recipe, from: prepared, image: image)
                    finish(recipe)
                case .review(let job):
                    let recipe = try await app.store.save(draft: prepared, image: image)
                    app.imports.markCompleted(job, recipe: recipe)
                    finish(recipe)
                }
            } catch {
                isSaving = false
                errorMessage = "Mise couldn’t save this recipe. Your library is unchanged. Please try again."
                Haptics.warning()
            }
        }
    }

    private func finish(_ recipe: Recipe) {
        isSaving = false
        Haptics.success()
        onSaved(recipe)
        dismiss()
    }

    private func saveLinkOnly() {
        guard let job = reviewJob, !isSaving else { return }
        isSaving = true
        var linkDraft = draft
        linkDraft.title = draft.displayTitle
        linkDraft.extractionMethod = .linkOnly
        linkDraft.confidence = .unverified
        linkDraft.ingredients = []
        linkDraft.instructions = []
        linkDraft.warnings = ["Only the source link was saved. Add ingredients and steps before cooking."]
        linkDraft.normalizeOrdering()
        Task {
            do {
                let recipe = try await app.store.save(draft: linkDraft, image: selectedImage)
                app.imports.markCompleted(job, recipe: recipe)
                finish(recipe)
            } catch {
                isSaving = false
                errorMessage = "Mise couldn’t save this link. Your library is unchanged. Please try again."
            }
        }
    }
}

// MARK: - Number field

struct EditorNumberField: View {
    let label: String
    @Binding var value: Int?
    @State private var text: String

    init(label: String, value: Binding<Int?>) {
        self.label = label
        _value = value
        _text = State(initialValue: value.wrappedValue.map(String.init) ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FieldLabel(text: label, optional: true)
            TextField("—", text: $text)
                .keyboardType(.numberPad)
                .foregroundStyle(MiseTheme.ink)
                .padding(.horizontal, 11)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(MiseTheme.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(MiseTheme.line, lineWidth: 1)
                )
                .onChange(of: text) { _, newValue in
                    let digits = newValue.filter(\.isNumber)
                    if digits != newValue { text = digits }
                    value = digits.isEmpty ? nil : Int(digits)
                }
                .onChange(of: value) { _, newValue in
                    let formatted = newValue.map(String.init) ?? ""
                    if text != formatted {
                        text = formatted
                    }
                }
                .accessibilityLabel(label)
        }
    }
}
