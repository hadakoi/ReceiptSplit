import SwiftData
import Vision
import VisionKit
import UIKit

struct OCRLine: Identifiable, Sendable {
    let id = UUID()
    var name: String
    var amount: Int
    var confidence: Float
}
struct OCRDraft: Identifiable, Sendable {
    let id = UUID()
    var merchant: String
    var lines: [OCRLine]
    var total: Int?
    var rawText: String
}
enum OCRFailure: LocalizedError {
    case unreadable, empty
    var errorDescription: String? {
        switch self {
        case .unreadable: return "This photo couldn’t be read. Try a clear, upright image of the receipt."
        case .empty: return "No text was found. Try a sharper photo with the entire receipt visible."
        }
    }
}
enum ReceiptOCR {
    static func recognize(_ images: [UIImage]) async throws -> OCRDraft {
        // Vision runs off the main thread; image pixels never leave this device.
        let data = images.compactMap { $0.jpegData(compressionQuality: 0.95) }
        return try await Task.detached(priority: .userInitiated) {
            var observations: [(String, Float)] = []
            for image in data {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = false
                request.recognitionLanguages = ["en-US"]
                try VNImageRequestHandler(data: image).perform([request])
                let results = (request.results ?? []).sorted { a, b in
                    abs(a.boundingBox.midY - b.boundingBox.midY) > 0.012 ? a.boundingBox.midY > b.boundingBox.midY : a.boundingBox.minX < b.boundingBox.minX
                }
                observations += results.compactMap { $0.topCandidates(1).first.map { ($0.string, $0.confidence) } }
            }
            guard !observations.isEmpty else { throw OCRFailure.empty }
            return parse(observations)
        }.value
    }
    static func parse(_ observations: [(String, Float)]) -> OCRDraft {
        var lines: [OCRLine] = []
        var total: Int?
        let pattern = #"(?:₹|Rs\.?|INR)?\s*([0-9][0-9,]*\.[0-9]{2})\s*$"#
        let regex = try! NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        for (text, confidence) in observations {
            let range = NSRange(text.startIndex..., in: text)
            guard let match = regex.firstMatch(in: text, range: range), let amountRange = Range(match.range(at: 1), in: text), let fullRange = Range(match.range, in: text), let amount = Money.parse(String(text[amountRange])) else { continue }
            let name = String(text[..<fullRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = name.lowercased()
            if lower.contains("total") {
                if !lower.contains("sub") { total = amount }
                continue
            }
            if ["cgst", "sgst", "gst", "tax", "tip", "discount", "service", "round", "cash", "change", "paid", "balance"].contains(where: { lower.contains($0) }) { continue }
            guard !name.isEmpty else { continue }
            lines.append(OCRLine(name: name, amount: amount, confidence: confidence))
        }
        return OCRDraft(merchant: observations.first?.0 ?? "Scanned receipt", lines: lines, total: total, rawText: observations.map(\.0).joined(separator: "\n"))
    }
}

