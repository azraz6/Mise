import SwiftUI

struct CookingModeView: View {
    @Environment(AppDependencies.self) private var app
    @Environment(\.dismiss) private var dismiss

    let recipe: Recipe

    @State private var stepIndex = 0
    @State private var didInitialize = false
    @State private var showIngredients = false
    @State private var isFinished = false
    @State private var timerEndDate: Date?
    @State private var pausedRemaining: Int?
    @State private var timerFinished = false
    @State private var idleTimerWasDisabled = false

    private var steps: [Instruction] {
        recipe.instructions
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.order < $1.order }
    }

    private var currentStep: Instruction? {
        guard steps.indices.contains(stepIndex) else { return steps.first }
        return steps[stepIndex]
    }

    private var progress: Double {
        guard !steps.isEmpty else { return 0 }
        return Double(stepIndex + 1) / Double(steps.count)
    }

    var body: some View {
        ZStack {
            PageBackground()
            if isFinished {
                finishedView
            } else if let step = currentStep {
                cookingContent(step)
            } else {
                EmptyStateView(
                    symbol: "list.number",
                    title: "No steps to cook",
                    message: "Add cooking steps to this recipe first.",
                    buttonTitle: "Close"
                ) {
                    dismiss()
                }
            }
        }
        .statusBarHidden(false)
        .onAppear(perform: prepare)
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = idleTimerWasDisabled
            if !isFinished, !steps.isEmpty {
                app.store.recordCookingStep(recipe: recipe, index: stepIndex, count: steps.count)
            }
        }
        .sheet(isPresented: $showIngredients) {
            CookingIngredientsSheet(recipe: recipe)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .task(id: timerEndDate) {
            guard let timerEndDate else { return }
            let nanoseconds = UInt64(max(0, timerEndDate.timeIntervalSinceNow) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            self.timerEndDate = nil
            self.pausedRemaining = 0
            self.timerFinished = true
            Haptics.success()
        }
    }

    // MARK: - Cooking

    private func cookingContent(_ step: Instruction) -> some View {
        VStack(spacing: 0) {
            topBar
            ProgressView(value: progress)
                .tint(MiseTheme.sage)
                .padding(.horizontal, 20)
                .accessibilityLabel("Cooking progress")
                .accessibilityValue("Step \(stepIndex + 1) of \(steps.count)")

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("STEP \(stepIndex + 1) OF \(steps.count)")
                            .font(.caption.weight(.semibold))
                            .tracking(1.2)
                            .foregroundStyle(MiseTheme.sage)
                        Text(recipe.title)
                            .font(.system(.title3, design: .serif, weight: .semibold))
                            .foregroundStyle(MiseTheme.secondaryInk)
                            .lineLimit(2)
                    }

                    Text(step.text)
                        .font(.system(.title2, design: .serif, weight: .regular))
                        .foregroundStyle(MiseTheme.ink)
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("cookingStepText")

                    if let duration = step.durationSeconds, duration > 0 {
                        timerCard(duration: duration)
                    }

                    if let notes = recipe.notes, !notes.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            Label("A note from your recipe", systemImage: "note.text")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(MiseTheme.secondaryInk)
                            Text(notes)
                                .font(.subheadline)
                                .foregroundStyle(MiseTheme.secondaryInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(MiseTheme.surface)
                        )
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 26)
                .padding(.bottom, 24)
                .frame(maxWidth: 680, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .gesture(
                DragGesture(minimumDistance: 60)
                    .onEnded { value in
                        if value.translation.width < -60 {
                            advance()
                        } else if value.translation.width > 60 {
                            goBack()
                        }
                    }
            )

            bottomBar
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(MiseTheme.ink)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(MiseTheme.surface))
                    .overlay(Circle().stroke(MiseTheme.line, lineWidth: 1))
            }
            .accessibilityLabel("Exit cooking mode")
            .accessibilityHint("Your current step is saved")

            Spacer()

            Button {
                showIngredients = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "list.bullet")
                    Text("Ingredients")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(MiseTheme.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Capsule().fill(MiseTheme.surface))
                .overlay(Capsule().stroke(MiseTheme.line, lineWidth: 1))
            }
            .accessibilityLabel("Show ingredients")
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            MiseDivider()
            HStack(spacing: 12) {
                Button {
                    goBack()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(stepIndex == 0 ? MiseTheme.secondaryInk.opacity(0.4) : MiseTheme.ink)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(MiseTheme.surface)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(MiseTheme.line, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .disabled(stepIndex == 0)
                .accessibilityLabel("Previous step")

                Button {
                    advance()
                } label: {
                    HStack(spacing: 8) {
                        Text(isLastStep ? "Finish cooking" : "Next step")
                        Image(systemName: isLastStep ? "checkmark" : "chevron.right")
                            .font(.caption.weight(.bold))
                    }
                }
                .buttonStyle(PrimaryButtonStyle(fill: isLastStep ? MiseTheme.sage : MiseTheme.ink))
                .accessibilityIdentifier("nextCookingStepButton")
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
        .background(.bar)
    }

    private var isLastStep: Bool {
        stepIndex >= steps.count - 1
    }

    // MARK: - Timer

    private func timerCard(duration: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Timer for this step", systemImage: "timer")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MiseTheme.secondaryInk)
                Spacer()
                if timerFinished {
                    Text("TIME’S UP")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.7)
                        .foregroundStyle(MiseTheme.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(MiseTheme.accent.opacity(0.12)))
                }
            }

            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                Text(timerText(at: context.date, duration: duration))
                    .font(.system(size: 48, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(timerFinished ? MiseTheme.accent : MiseTheme.ink)
                    .contentTransition(.numericText())
                    .accessibilityLabel("Timer")
                    .accessibilityValue(timerText(at: context.date, duration: duration))
            }

            HStack(spacing: 9) {
                if timerEndDate == nil && !timerFinished {
                    Button {
                        startTimer(remaining: pausedRemaining ?? duration)
                    } label: {
                        Label(pausedRemaining == nil ? "Start timer" : "Resume", systemImage: "play.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(MiseTheme.background)
                            .frame(maxWidth: .infinity, minHeight: 42)
                            .background(
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill(MiseTheme.ink)
                            )
                    }
                    .buttonStyle(.plain)
                } else if timerEndDate != nil {
                    Button {
                        pauseTimer(duration: duration)
                    } label: {
                        Label("Pause", systemImage: "pause.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(MiseTheme.ink)
                            .frame(maxWidth: .infinity, minHeight: 42)
                            .background(
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill(MiseTheme.raisedSurface)
                            )
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    resetTimer()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(MiseTheme.secondaryInk)
                        .frame(width: 44, height: 42)
                        .background(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(MiseTheme.raisedSurface)
                        )
                }
                .accessibilityLabel("Reset timer")
            }

            Text("The timer runs while Mise is open. Mise doesn’t send background notifications.")
                .font(.caption2)
                .foregroundStyle(MiseTheme.secondaryInk)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(MiseTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(MiseTheme.line, lineWidth: 1)
        )
    }

    private func timerText(at date: Date, duration: Int) -> String {
        let remaining: Int
        if let timerEndDate {
            remaining = max(0, Int(ceil(timerEndDate.timeIntervalSince(date))))
        } else if let pausedRemaining {
            remaining = pausedRemaining
        } else {
            remaining = duration
        }
        let minutes = remaining / 60
        let seconds = remaining % 60
        if minutes >= 60 {
            let hours = minutes / 60
            return String(format: "%d:%02d:%02d", hours, minutes % 60, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func startTimer(remaining: Int) {
        timerFinished = false
        pausedRemaining = nil
        timerEndDate = Date().addingTimeInterval(TimeInterval(max(1, remaining)))
        Haptics.tap()
    }

    private func pauseTimer(duration: Int) {
        guard let timerEndDate else { return }
        pausedRemaining = max(0, Int(ceil(timerEndDate.timeIntervalSinceNow)))
        self.timerEndDate = nil
        Haptics.tap()
    }

    private func resetTimer() {
        timerEndDate = nil
        pausedRemaining = nil
        timerFinished = false
    }

    // MARK: - Navigation

    private func prepare() {
        guard !didInitialize else { return }
        didInitialize = true
        if steps.isEmpty {
            stepIndex = 0
        } else if recipe.hasCookingProgress {
            stepIndex = min(max(recipe.cookingStepIndex, 0), steps.count - 1)
        } else {
            stepIndex = 0
        }
        idleTimerWasDisabled = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = true
        resetTimer()
    }

    private func advance() {
        guard !steps.isEmpty else { return }
        if isLastStep {
            finishCooking()
        } else {
            stepIndex += 1
            resetTimer()
            app.store.recordCookingStep(recipe: recipe, index: stepIndex, count: steps.count)
            Haptics.tap()
        }
    }

    private func goBack() {
        guard stepIndex > 0 else { return }
        stepIndex -= 1
        resetTimer()
        app.store.recordCookingStep(recipe: recipe, index: stepIndex, count: steps.count)
        Haptics.tap()
    }

    private func finishCooking() {
        app.store.finishCooking(recipe: recipe)
        Haptics.success()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) {
            isFinished = true
        }
    }

    // MARK: - Finished

    private var finishedView: some View {
        VStack(spacing: 22) {
            Spacer()
            ZStack {
                Circle()
                    .fill(MiseTheme.sage.opacity(0.12))
                    .frame(width: 112, height: 112)
                Image(systemName: "checkmark")
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(MiseTheme.sage)
            }
            VStack(spacing: 8) {
                Text("Dinner is served.")
                    .font(.system(.largeTitle, design: .serif, weight: .semibold))
                    .foregroundStyle(MiseTheme.ink)
                    .multilineTextAlignment(.center)
                Text(recipe.title)
                    .font(.title3)
                    .foregroundStyle(MiseTheme.secondaryInk)
                    .multilineTextAlignment(.center)
            }
            Spacer()
            VStack(spacing: 10) {
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle(fill: MiseTheme.ink))
                .accessibilityIdentifier("finishCookingButton")
                Text("Saved as cooked in your library.")
                    .font(.caption)
                    .foregroundStyle(MiseTheme.secondaryInk)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .frame(maxWidth: 420)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Ingredients drawer

struct CookingIngredientsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let recipe: Recipe

    private var ingredients: [Ingredient] {
        recipe.ingredients
            .filter { !$0.originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.order < $1.order }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let servings = recipe.originalServings {
                        Text("As written for \(servings) servings")
                            .font(.caption)
                            .foregroundStyle(MiseTheme.secondaryInk)
                            .padding(.bottom, 10)
                    }
                    ForEach(Array(ingredients.enumerated()), id: \.element.id) { index, ingredient in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Circle()
                                .fill(MiseTheme.accent.opacity(0.65))
                                .frame(width: 5, height: 5)
                                .padding(.top, 7)
                            Text(ingredient.originalText)
                                .font(.body)
                                .foregroundStyle(MiseTheme.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 10)
                        if index < ingredients.count - 1 {
                            MiseDivider().padding(.leading, 15)
                        }
                    }
                }
                .padding(20)
            }
            .background(PageBackground())
            .navigationTitle("Ingredients")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
