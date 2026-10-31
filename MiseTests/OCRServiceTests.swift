import UIKit
import XCTest
@testable import Mise

final class OCRServiceTests: XCTestCase {
    func testNoImagesThrows() async {
        do {
            _ = try await OCRService.shared.recognizeText(in: [])
            XCTFail("Expected noImages")
        } catch let error as OCRServiceError {
            XCTAssertEqual(error, .noImages)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCombinedTextUsesPageOrder() {
        let pages = [
            OCRPageResult(pageIndex: 1, text: "Second page"),
            OCRPageResult(pageIndex: 0, text: "First page")
        ]
        XCTAssertEqual(OCRService.combinedText(from: pages), "First page\n\nSecond page")
    }

    func testRecognizesRenderedRecipeText() async throws {
        let image = renderTextImage(lines: [
            "2 cups all-purpose flour",
            "1 teaspoon fine salt"
        ])
        let pages = try await OCRService.shared.recognizeText(in: [image])
        XCTAssertEqual(pages.count, 1)
        let text = OCRService.combinedText(from: pages).lowercased()
        XCTAssertTrue(text.contains("flour"), "Recognized text was: \(text)")
        XCTAssertTrue(text.contains("salt"), "Recognized text was: \(text)")
        XCTAssertTrue(text.contains("cups") || text.contains("cup"), "Recognized text was: \(text)")
    }

    private func renderTextImage(lines: [String]) -> UIImage {
        let size = CGSize(width: 1200, height: 500)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 72, weight: .semibold),
                .foregroundColor: UIColor.black
            ]
            for (index, line) in lines.enumerated() {
                let y = CGFloat(60 + index * 120)
                (line as NSString).draw(at: CGPoint(x: 50, y: y), withAttributes: attributes)
            }
        }
    }
}
