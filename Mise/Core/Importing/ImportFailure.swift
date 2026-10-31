import Foundation

enum ImportFailure: Error, Equatable {
    case invalidInput(ImportInputError)
    case offline
    case timedOut
    case cancelled
    case httpStatus(Int)
    case unsupportedContent(String?)
    case responseTooLarge
    case unreadablePage
    case noRecipeFound
    case socialNeedsManual(RecipeSourceType)
    case ocrFailed
    case imageUnavailable
    case blocked(String?)
    case importLimitReached

    var title: String {
        switch self {
        case .invalidInput: return "Check that link"
        case .offline: return "You’re offline"
        case .timedOut: return "The page took too long"
        case .cancelled: return "Import cancelled"
        case .httpStatus(401), .httpStatus(403), .blocked: return "This page is restricted"
        case .httpStatus(404), .httpStatus(410): return "That page wasn’t found"
        case .httpStatus(429): return "The site is asking us to slow down"
        case .httpStatus: return "The site didn’t respond"
        case .unsupportedContent: return "This isn’t a webpage"
        case .responseTooLarge: return "This page is too large"
        case .unreadablePage: return "We couldn’t read this page"
        case .noRecipeFound: return "No recipe was found"
        case .socialNeedsManual: return "This link needs a hand"
        case .ocrFailed: return "No text was recognized"
        case .imageUnavailable: return "That image couldn’t be opened"
        case .importLimitReached: return "This month’s free imports are used"
        }
    }

    var message: String {
        switch self {
        case .invalidInput(let error):
            return [error.errorDescription, error.recoverySuggestion].compactMap { $0 }.joined(separator: " ")
        case .offline:
            return "Connect to the internet and try again. Your link can still be saved as a manual recipe."
        case .timedOut:
            return "The site didn’t finish loading within 25 seconds. Try again, or paste the recipe text instead."
        case .cancelled:
            return "The import was stopped before it finished."
        case .httpStatus(401):
            return "The page requires a login. Mise doesn’t sign in for you. Save the link, then paste the recipe text or use a screenshot."
        case .httpStatus(403):
            return "The site blocked automatic reading. Mise won’t bypass that. Paste the recipe text or try a screenshot instead."
        case .httpStatus(404), .httpStatus(410):
            return "The link may be broken or the page may have moved. Check the address, or paste the recipe text."
        case .httpStatus(429):
            return "Wait a minute before trying again. You can also paste the recipe text or use a screenshot."
        case .httpStatus(500...599):
            return "The website had a server problem. Try again later, or paste the recipe text."
        case .httpStatus:
            return "The site returned an unexpected response. Try again, or paste the recipe text."
        case .unsupportedContent(let type):
            let suffix = type.map { " (\($0))" } ?? ""
            return "That link points to a file or media type Mise can’t read\(suffix). Use a recipe webpage, pasted text, or a screenshot."
        case .responseTooLarge:
            return "The page was larger than the 8 MB safety limit. Paste the recipe text instead."
        case .unreadablePage:
            return "The page loaded, but its text couldn’t be read reliably. Paste the recipe text or use a screenshot."
        case .noRecipeFound:
            return "Mise couldn’t find ingredients and steps on that page. Save the link and add the recipe from pasted text or a screenshot."
        case .socialNeedsManual(let source):
            return "\(source.displayName) doesn’t provide the full recipe to third-party apps. Mise can save the link now, and you can paste the caption, use a screenshot, or write the recipe yourself. No login or scraped media is used."
        case .ocrFailed:
            return "The image contained too little readable text. Try a sharper screenshot with larger text, or paste the caption instead."
        case .imageUnavailable:
            return "The image data couldn’t be read. Try choosing it again from Photos."
        case .importLimitReached:
            return "You’ve used all \(FreeTier.automaticImportsPerMonth) automatic imports included this month. Mise Premium removes the cap, or you can add the recipe manually — manual entry is always unlimited. Your free imports reset at the start of next month."
        case .blocked(let reason):
            return reason ?? "The site blocked automatic reading. Mise won’t bypass access controls. Paste the recipe text or use a screenshot instead."
        }
    }

    var retryEligible: Bool {
        switch self {
        case .offline, .timedOut, .httpStatus(429), .httpStatus(500...599), .unreadablePage:
            return true
        case .httpStatus, .invalidInput, .unsupportedContent, .responseTooLarge, .noRecipeFound,
             .socialNeedsManual, .ocrFailed, .imageUnavailable, .blocked, .cancelled, .importLimitReached:
            return false
        }
    }

    var allowsLinkSave: Bool {
        switch self {
        case .socialNeedsManual, .httpStatus(401), .httpStatus(403), .blocked,
             .noRecipeFound, .timedOut, .offline, .httpStatus:
            return true
        default:
            return false
        }
    }
}

struct PageExtraction: Sendable {
    var drafts: [RecipeDraft]
    var pageTitle: String
    var pageDescription: String
    var imageURLString: String?
    var method: ExtractionMethod
    var warnings: [String]
    var foundStructuredData: Bool

    var bestDraft: RecipeDraft? { drafts.first }
}

struct TextParseOutcome: Sendable {
    var draft: RecipeDraft
    var warnings: [String]
}
