import SwiftData
import Vision
import VisionKit
import UIKit

struct OCRLine: Identifiable, Sendable {
    let id = UUID()
    var name: String
    var amount: Int
    var confidence: Float
    var quantity: Int = 1
    var unitPrice: Int? = nil
}
enum OCRChargeKind: String, Sendable {
    case cgst = "CGST", sgst = "SGST", service = "Service charge", discount = "Discount", rounding = "Rounding", tip = "Tip"
}
struct OCRCharge: Identifiable, Sendable {
    let id = UUID()
    var kind: OCRChargeKind
    var amount: Int
    var source: String
    var confidence: Float
}
struct OCRTextBox {
    var text: String
    var confidence: Float
    var bounds: CGRect
}
struct OCRDraft: Identifiable, Sendable {
    let id = UUID()
    var merchant: String
    var lines: [OCRLine]
    var total: Int?
    var rawText: String
    var charges: [OCRCharge] = []
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
                let boxes = (request.results ?? []).compactMap { result -> OCRTextBox? in
                    guard let candidate = result.topCandidates(1).first else { return nil }
                    return OCRTextBox(text: candidate.string, confidence: candidate.confidence, bounds: result.boundingBox)
                }
                observations += groupRows(boxes)
            }
            guard !observations.isEmpty else { throw OCRFailure.empty }
            return parse(observations)
        }.value
    }
    // Vision may return the label and amount as separate observations. Associate
    // boxes on the same baseline, separately for each page, before parsing.
    static func groupRows(_ boxes: [OCRTextBox]) -> [(String, Float)] {
        var rows: [[OCRTextBox]] = []
        for box in boxes.sorted(by: { $0.bounds.midY > $1.bounds.midY }) {
            if let index = rows.firstIndex(where: { row in
                guard let anchor = row.first else { return false }
                return abs(anchor.bounds.midY - box.bounds.midY) <= max(0.003, min(anchor.bounds.height, box.bounds.height) * 0.5)
            }) { rows[index].append(box) } else { rows.append([box]) }
        }
        return rows.map { row in
            let ordered = row.sorted { $0.bounds.minX < $1.bounds.minX }
            return (ordered.map(\.text).joined(separator: "  "), ordered.map(\.confidence).min() ?? 0)
        }
    }
    static func parse(_ observations: [(String, Float)]) -> OCRDraft {
        var lines: [OCRLine] = []
        var charges: [OCRCharge] = []
        var total: Int?
        var inItemTable = false
        let pattern = #"(?:₹|Rs\.?|INR)?\s*(-?[0-9][0-9,]*\.[0-9]{2})\s*$"#
        let regex = try! NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        let tableItemRegex = try! NSRegularExpression(pattern: #"^\s*(.*?[A-Za-z\)])\s+(\d[\d,]*(?:\.\d{2})?(?:\s+\d[\d,]*(?:\.\d{2})?)*)\s*$"#)
        for (text, confidence) in observations {
            let normalized = text.lowercased()
            if (normalized.contains("particular") || normalized.contains("item")) && (normalized.contains("qty") || normalized.contains("quantity")) && (normalized.contains("amount") || normalized.contains("rate")) { inItemTable = true; continue }
            if normalized.contains("subtotal") || normalized.contains("sub total") { inItemTable = false }
            let range = NSRange(text.startIndex..., in: text)
            if inItemTable, let match = tableItemRegex.firstMatch(in: text, range: range), let nameRange = Range(match.range(at: 1), in: text), let valuesRange = Range(match.range(at: 2), in: text) {
                let name = String(text[nameRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                let parts = text[valuesRange].split(whereSeparator: { $0.isWhitespace }).map(String.init)
                if parts.count <= 3, let amountText = parts.last, let amount = Money.parse(amountText) {
                    // A lone small integer next to a name is often a quantity,
                    // not a price. Leave it for manual review rather than guess.
                    if parts.count == 1 && !amountText.contains(".") && amount < 1000 { continue }
                    var line = OCRLine(name: name, amount: amount, confidence: confidence)
                    if parts.count == 3, let quantity = Int(parts[0]), (1...999).contains(quantity), let price = Money.parse(parts[1]), quantity * price == amount {
                        line.quantity = quantity; line.unitPrice = price
                    }
                    lines.append(line); continue
                }
            }
            guard let match = regex.firstMatch(in: text, range: range), let amountRange = Range(match.range(at: 1), in: text), let fullRange = Range(match.range, in: text), let amount = Money.parse(String(text[amountRange]), signed: true) else { continue }
            let name = String(text[..<fullRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = name.lowercased()
            let compact = lower.replacingOccurrences(of: " ", with: "")
            let kind: OCRChargeKind?
            if compact.contains("cgst") { kind = .cgst }
            else if compact.contains("sgst") { kind = .sgst }
            else if lower.contains("service") && (lower.contains("charge") || lower.contains("fee")) { kind = .service }
            else if lower.contains("discount") || lower.contains("disc ") { kind = .discount }
            else if lower.contains("round") { kind = .rounding }
            else if lower.contains("tip") || lower.contains("gratuity") { kind = .tip }
            else { kind = nil }
            if let kind {
                guard amount >= 0 || kind == .rounding || kind == .discount else { continue }
                charges.append(OCRCharge(kind: kind, amount: kind == .discount ? abs(amount) : amount, source: text, confidence: confidence))
                continue
            }
            if lower.contains("total") {
                if !lower.contains("sub") { total = amount }
                continue
            }
            if ["cgst", "sgst", "gst", "tax", "tip", "discount", "service", "round", "cash", "change", "paid", "balance"].contains(where: { lower.contains($0) }) { continue }
            guard !name.isEmpty, amount >= 0 else { continue }
            lines.append(OCRLine(name: name, amount: amount, confidence: confidence))
        }
        return OCRDraft(merchant: observations.first?.0 ?? "Scanned receipt", lines: lines, total: total, rawText: observations.map(\.0).joined(separator: "\n"), charges: charges)
    }
}

