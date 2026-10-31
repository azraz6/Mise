import SwiftUI

/// Covers only the status-bar area with the page background so scrolling
/// content never collides with the clock or system icons.
struct StatusBarScrim: View {
    var body: some View {
        GeometryReader { proxy in
            let inset = max(proxy.safeAreaInsets.top, 20)
            VStack(spacing: 0) {
                MiseTheme.background
                    .frame(height: inset)
                LinearGradient(
                    colors: [MiseTheme.background, MiseTheme.background.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 8)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .ignoresSafeArea(edges: .top)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension View {
    func statusBarScrim() -> some View {
        overlay(alignment: .top) {
            StatusBarScrim()
        }
    }
}

struct RecipeCoverImage: View {
    var filename: String?
    var assetName: String?
    var cornerRadius: CGFloat = 16
    var symbolSize: CGFloat = 24

    @State private var image: UIImage?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(MiseTheme.raisedSurface)
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else if let assetName, let bundled = UIImage(named: assetName) {
                    Image(uiImage: bundled)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "fork.knife")
                        .font(.system(size: symbolSize, weight: .light))
                        .foregroundStyle(MiseTheme.sage.opacity(0.55))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .clipped()
        }
        .accessibilityHidden(true)
        .task(id: filename) {
            guard let filename else { image = nil; return }
            image = await ImageStore.shared.loadImage(named: filename)
        }
    }
}

struct RecipeRow: View {
    let recipe: Recipe
    var showSource: Bool = true
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: 14) {
            RecipeCoverImage(
                filename: recipe.coverImageFilename,
                assetName: recipe.coverAssetName,
                cornerRadius: 12,
                symbolSize: 19
            )
            .frame(width: 78, height: 78)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Text(recipe.title)
                        .font(.system(.body, design: .serif, weight: .semibold))
                        .foregroundStyle(MiseTheme.ink)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 4 : 3)
                        .accessibilityIdentifier("recipeTitle")
                    if recipe.isFavourite {
                        Image(systemName: "heart.fill")
                            .font(.caption2)
                            .foregroundStyle(MiseTheme.accent)
                            .accessibilityLabel("Favourite")
                    }
                }
                HStack(spacing: 8) {
                    if let total = recipe.totalMinutes {
                        Label("\(total) min", systemImage: "clock")
                    } else if let servings = recipe.originalServings {
                        Label("Serves \(servings)", systemImage: "person.2")
                    }
                    if showSource, !recipe.sourceType.isSocial, recipe.sourceType != .manual {
                        Text("·")
                    }
                    if showSource, recipe.sourceType.isSocial || recipe.sourceType == .website {
                        Text(recipe.sourceType.displayName)
                    }
                }
                .font(.caption)
                .foregroundStyle(MiseTheme.secondaryInk)
                .lineLimit(1)
                if recipe.extractionMethod == .linkOnly {
                    Text("Link only · add details")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(MiseTheme.accent)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(MiseTheme.secondaryInk.opacity(0.55))
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("recipeRow")
    }
}

struct RecipeCard: View {
    let recipe: Recipe
    var width: CGFloat = 172
    var titleLineLimit: Int = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RecipeCoverImage(
                filename: recipe.coverImageFilename,
                assetName: recipe.coverAssetName,
                cornerRadius: 14,
                symbolSize: 22
            )
            .frame(width: width, height: width * 0.78)
            VStack(alignment: .leading, spacing: 4) {
                Text(recipe.title)
                    .font(.system(.body, design: .serif, weight: .semibold))
                    .foregroundStyle(MiseTheme.ink)
                    .lineLimit(titleLineLimit)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    if let total = recipe.totalMinutes {
                        Text("\(total) min")
                    } else if let servings = recipe.originalServings {
                        Text("Serves \(servings)")
                    }
                    if recipe.isFavourite {
                        Image(systemName: "heart.fill").foregroundStyle(MiseTheme.accent)
                    }
                }
                .font(.caption)
                .foregroundStyle(MiseTheme.secondaryInk)
            }
        }
        .frame(width: width, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(recipe.title). \(recipe.totalMinutes.map { "\($0) minutes." } ?? "")")
    }
}

struct StatusBadge: View {
    let status: ImportStatus

    var body: some View {
        Text(status.displayName)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.12)))
    }

    private var color: Color {
        switch status {
        case .failed: return MiseTheme.accent
        case .needsReview, .extracted: return MiseTheme.warning
        case .linkSaved: return MiseTheme.sage
        case .completed: return MiseTheme.positive
        case .processing, .queued: return MiseTheme.secondaryInk
        }
    }
}
