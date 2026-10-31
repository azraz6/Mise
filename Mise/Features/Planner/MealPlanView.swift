import SwiftData
import SwiftUI

struct MealPlanView: View {
    @Environment(AppDependencies.self) private var app
    @Environment(AppRouter.self) private var router

    @Query private var entries: [MealPlanEntry]
    @Query(sort: \Recipe.dateAdded, order: .reverse) private var recipes: [Recipe]

    @State private var weekStart = MealPlanCalendar.startOfWeek(containing: Date())
    @State private var slotSelection: SlotSelection?
    @State private var generatedList: ShoppingList?
    @State private var showGeneratedAlert = false

    private struct SlotSelection: Identifiable {
        let dayKey: String
        let day: Date
        let slot: MealSlot
        let existingRecipeID: UUID?

        var id: String { "\(dayKey)-\(slot.rawValue)" }
    }

    private var days: [Date] {
        MealPlanCalendar.days(inWeekStarting: weekStart)
    }

    private var weekEntries: [MealPlanEntry] {
        let keys = Set(days.map { MealPlanCalendar.dayKey(for: $0) })
        return entries.filter { keys.contains($0.dayKey) }
    }

    private var recipesByID: [UUID: Recipe] {
        Dictionary(uniqueKeysWithValues: recipes.map { ($0.id, $0) })
    }

    private var plannedCount: Int {
        weekEntries.count
    }

    private var uniqueRecipeCount: Int {
        Set(weekEntries.map(\.recipeID)).count
    }

    private var isCurrentWeek: Bool {
        Calendar.current.isDate(weekStart, inSameDayAs: MealPlanCalendar.startOfWeek(containing: Date()))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    weekNavigator
                    summaryCard
                    VStack(spacing: 12) {
                        ForEach(days, id: \.self) { day in
                            dayCard(day)
                        }
                    }
                    Text("Meal plans are flexible. Move things around whenever the week changes.")
                        .font(.caption2)
                        .foregroundStyle(MiseTheme.secondaryInk)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 36)
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(PageBackground())
            .statusBarScrim()
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(item: $slotSelection) { selection in
            MealRecipePickerView(
                dayKey: selection.dayKey,
                day: selection.day,
                slot: selection.slot,
                existingRecipeID: selection.existingRecipeID
            )
            .environment(app)
            .environment(router)
            .modelContainer(app.container)
        }
        .alert("Shopping list ready", isPresented: $showGeneratedAlert) {
            Button("Not now", role: .cancel) { generatedList = nil }
            Button("View list") {
                generatedList = nil
                router.selectedTab = .shopping
            }
        } message: {
            Text("Mise created “\(generatedList?.name ?? "Meal plan shop")” with the ingredients from this week’s meals.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Meal plan")
                    .font(.system(.largeTitle, design: .serif, weight: .semibold))
                    .foregroundStyle(MiseTheme.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(MealPlanCalendar.weekTitle(for: weekStart))
                    .font(.subheadline)
                    .foregroundStyle(MiseTheme.secondaryInk)
            }
            Spacer()
            Button {
                router.showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(MiseTheme.ink)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(MiseTheme.surface))
                    .overlay(Circle().stroke(MiseTheme.line, lineWidth: 1))
            }
            .accessibilityLabel("Settings")
        }
    }

    private var weekNavigator: some View {
        HStack(spacing: 10) {
            Button {
                shiftWeek(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(MiseTheme.ink)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(MiseTheme.surface))
                    .overlay(Circle().stroke(MiseTheme.line, lineWidth: 1))
            }
            .accessibilityLabel("Previous week")

            VStack(spacing: 1) {
                Text(isCurrentWeek ? "This week" : "Week")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isCurrentWeek ? MiseTheme.sage : MiseTheme.secondaryInk)
                Text(MealPlanCalendar.weekTitle(for: weekStart))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(MiseTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)

            Button {
                shiftWeek(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(MiseTheme.ink)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(MiseTheme.surface))
                    .overlay(Circle().stroke(MiseTheme.line, lineWidth: 1))
            }
            .accessibilityLabel("Next week")

            if !isCurrentWeek {
                Button("Today") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        weekStart = MealPlanCalendar.startOfWeek(containing: Date())
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(MiseTheme.accent)
            }
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(plannedCount) of 21 meals planned")
                        .font(.system(.title3, design: .serif, weight: .semibold))
                        .foregroundStyle(MiseTheme.ink)
                    Text(uniqueRecipeCount == 1 ? "1 recipe this week" : "\(uniqueRecipeCount) recipes this week")
                        .font(.caption)
                        .foregroundStyle(MiseTheme.secondaryInk)
                }
                Spacer()
                Image(systemName: "calendar")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(MiseTheme.sage)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(MiseTheme.sage.opacity(0.1)))
            }

            ProgressView(value: Double(plannedCount), total: 21)
                .tint(MiseTheme.sage)

            Button {
                generateShoppingList()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "cart.badge.plus")
                    Text("Shop this week")
                }
            }
            .buttonStyle(PrimaryButtonStyle(fill: plannedCount == 0 ? MiseTheme.raisedSurface : MiseTheme.ink, foreground: plannedCount == 0 ? MiseTheme.secondaryInk : MiseTheme.background))
            .disabled(plannedCount == 0)
            .accessibilityIdentifier("mealPlanShopButton")
            .accessibilityHint(plannedCount == 0 ? "Add at least one meal first" : "Creates a shopping list from this week’s recipes")
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(MiseTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(MiseTheme.line, lineWidth: 1)
        )
    }

    // MARK: - Days

    private func dayCard(_ day: Date) -> some View {
        let key = MealPlanCalendar.dayKey(for: day)
        let isToday = MealPlanCalendar.isToday(day)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(day.formatted(.dateTime.weekday(.wide)))
                    .font(.system(.headline, design: .serif, weight: .semibold))
                    .foregroundStyle(MiseTheme.ink)
                Text(day.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.caption)
                    .foregroundStyle(MiseTheme.secondaryInk)
                if isToday {
                    Text("TODAY")
                        .font(.caption2.weight(.bold))
                        .tracking(0.6)
                        .foregroundStyle(MiseTheme.sage)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(MiseTheme.sage.opacity(0.12)))
                }
                Spacer()
            }
            .padding(.horizontal, 2)

            VStack(spacing: 0) {
                ForEach(MealSlot.allCases) { slot in
                    let entry = entries.first { $0.dayKey == key && $0.slot == slot }
                    slotRow(dayKey: key, day: day, slot: slot, entry: entry)
                    if slot != MealSlot.allCases.last {
                        MiseDivider().padding(.leading, 34)
                    }
                }
            }
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(MiseTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(isToday ? MiseTheme.sage.opacity(0.4) : MiseTheme.line, lineWidth: 1)
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(day.formatted(.dateTime.weekday(.wide).month(.wide).day()))\(isToday ? ", today" : "")")
    }

    @ViewBuilder
    private func slotRow(dayKey: String, day: Date, slot: MealSlot, entry: MealPlanEntry?) -> some View {
        if let entry, let recipe = recipesByID[entry.recipeID] {
            HStack(spacing: 10) {
                Image(systemName: slot.symbolName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MiseTheme.sage)
                    .frame(width: 24)
                NavigationLink {
                    RecipeDetailView(recipe: recipe)
                } label: {
                    HStack(spacing: 10) {
                        RecipeCoverImage(
                            filename: recipe.coverImageFilename,
                            assetName: recipe.coverAssetName,
                            cornerRadius: 7
                        )
                        .frame(width: 34, height: 34)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(slot.displayName.uppercased())
                                .font(.caption2.weight(.semibold))
                                .tracking(0.6)
                                .foregroundStyle(MiseTheme.secondaryInk)
                            Text(recipe.title)
                                .font(.subheadline)
                                .foregroundStyle(MiseTheme.ink)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(slot.displayName): \(recipe.title)")

                Menu {
                    Button {
                        slotSelection = SlotSelection(dayKey: dayKey, day: day, slot: slot, existingRecipeID: recipe.id)
                    } label: {
                        Label("Change meal", systemImage: "arrow.triangle.2.circlepath")
                    }
                    Button(role: .destructive) {
                        app.store.removeMeal(entry)
                        Haptics.tap()
                    } label: {
                        Label("Remove from plan", systemImage: "minus.circle")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(MiseTheme.secondaryInk.opacity(0.6))
                        .frame(width: 28, height: 30)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Options for \(slot.displayName)")
            }
            .padding(.vertical, 9)
        } else if entry != nil {
            HStack(spacing: 10) {
                Image(systemName: slot.symbolName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MiseTheme.sage)
                    .frame(width: 24)
                Text("This recipe is no longer available")
                    .font(.caption)
                    .foregroundStyle(MiseTheme.secondaryInk)
                Spacer()
                Button {
                    app.store.removeMeal(entry!)
                } label: {
                    Image(systemName: "xmark.circle")
                        .foregroundStyle(MiseTheme.secondaryInk)
                }
                .accessibilityLabel("Remove missing meal")
            }
            .padding(.vertical, 11)
        } else {
            Button {
                slotSelection = SlotSelection(dayKey: dayKey, day: day, slot: slot, existingRecipeID: nil)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: slot.symbolName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MiseTheme.secondaryInk.opacity(0.55))
                        .frame(width: 24)
                    Text("Add \(slot.displayName.lowercased())")
                        .font(.caption)
                        .foregroundStyle(MiseTheme.secondaryInk)
                    Spacer()
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(MiseTheme.sage)
                }
                .padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add \(slot.displayName.lowercased()) for \(day.formatted(.dateTime.weekday(.wide)))")
        }
    }

    // MARK: - Actions

    private func shiftWeek(by amount: Int) {
        guard let newStart = Calendar.current.date(byAdding: .day, value: amount * 7, to: weekStart) else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            weekStart = MealPlanCalendar.startOfWeek(containing: newStart)
        }
    }

    private func generateShoppingList() {
        let selected = weekEntries
        guard !selected.isEmpty else { return }
        let name = "Meal plan · \(MealPlanCalendar.weekTitle(for: weekStart))"
        let list = app.store.generateShoppingList(from: selected, name: name)
        generatedList = list
        showGeneratedAlert = true
        Haptics.success()
    }
}

// MARK: - Choose a recipe

struct MealRecipePickerView: View {
    @Environment(AppDependencies.self) private var app
    @Environment(\.dismiss) private var dismiss

    let dayKey: String
    let day: Date
    let slot: MealSlot
    let existingRecipeID: UUID?

    @Query(sort: \Recipe.dateAdded, order: .reverse) private var recipes: [Recipe]
    @State private var searchText = ""

    private var visible: [Recipe] {
        RecipeSearch.apply(recipes, filter: RecipeFilter(query: searchText), sort: .title)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 9) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(MiseTheme.secondaryInk)
                        TextField("Search recipes", text: $searchText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    .padding(.horizontal, 13)
                    .frame(minHeight: 46)
                    .background(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(MiseTheme.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .stroke(MiseTheme.line, lineWidth: 1)
                    )

                    if existingRecipeID != nil {
                        Button(role: .destructive) {
                            if let entry = app.store.mealEntry(dayKey: dayKey, slot: slot) {
                                app.store.removeMeal(entry)
                            }
                            dismiss()
                        } label: {
                            Label("Remove from this slot", systemImage: "minus.circle")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(MiseTheme.accent)
                        }
                    }

                    if visible.isEmpty {
                        EmptyStateView(
                            symbol: "book.closed",
                            title: "No recipes found",
                            message: "Try another search, or add a recipe to your library first."
                        )
                        .padding(.top, 20)
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(visible.enumerated()), id: \.element.id) { index, recipe in
                                Button {
                                    choose(recipe)
                                } label: {
                                    HStack(spacing: 12) {
                                        RecipeCoverImage(
                                            filename: recipe.coverImageFilename,
                                            assetName: recipe.coverAssetName,
                                            cornerRadius: 10
                                        )
                                        .frame(width: 54, height: 54)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(recipe.title)
                                                .font(.subheadline.weight(.medium))
                                                .foregroundStyle(MiseTheme.ink)
                                                .lineLimit(2)
                                            HStack(spacing: 8) {
                                                if let total = recipe.totalMinutes {
                                                    Text("\(total) min")
                                                }
                                                if let servings = recipe.originalServings {
                                                    Text("Serves \(servings)")
                                                }
                                            }
                                            .font(.caption2)
                                            .foregroundStyle(MiseTheme.secondaryInk)
                                        }
                                        Spacer(minLength: 0)
                                        if existingRecipeID == recipe.id {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(MiseTheme.sage)
                                        }
                                    }
                                    .padding(.vertical, 8)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("mealRecipeOption")
                                if index < visible.count - 1 {
                                    MiseDivider().padding(.leading, 66)
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(PageBackground())
            .navigationTitle("\(slot.displayName) · \(day.formatted(.dateTime.weekday(.abbreviated).day()))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(MiseTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func choose(_ recipe: Recipe) {
        app.store.setMeal(recipeID: recipe.id, dayKey: dayKey, slot: slot)
        Haptics.success()
        dismiss()
    }
}
