import XCTest
import SwiftData
import UIKit
@testable import ReceiptSplit

final class ReceiptSplitTests: XCTestCase {
    @MainActor func testStoryboardScenesAndOCRImportReview() throws {
        let storyboard = UIStoryboard(name: "Main", bundle: Bundle(for: AppDelegate.self))
        let navigation = try XCTUnwrap(storyboard.instantiateInitialViewController() as? UINavigationController)
        XCTAssertTrue(navigation.viewControllers.first is ReceiptsViewController)
        for id in ["Detail", "ReceiptEditor", "ItemEditor", "People", "PersonEditor", "Settlement", "OCRReview"] {
            XCTAssertTrue(storyboard.instantiateViewController(withIdentifier: id) is StoryboardTableController, id)
        }
        let context = (UIApplication.shared.delegate as! AppDelegate).container.mainContext
        let receipt = Receipt(merchant: "Original")
        context.insert(receipt)
        let draft = ReceiptOCR.parse([("Cafe", 0.99), ("Coffee 120.00", 0.9), ("Tea 50.00", 0.6), ("TOTAL 170.00", 0.9)])
        let review = try XCTUnwrap(storyboard.instantiateViewController(withIdentifier: "OCRReview") as? OCRReviewViewController)
        review.receipt = receipt; review.draft = draft; review.loadViewIfNeeded()
        review.tableView(review.tableView, didSelectRowAt: IndexPath(row: 0, section: 1)) // merchant
        review.tableView(review.tableView, didSelectRowAt: IndexPath(row: 1, section: 1)) // total
        review.tableView(review.tableView, didSelectRowAt: IndexPath(row: 1, section: 2)) // deselect tea
        review.importItems()
        XCTAssertEqual(receipt.merchant, "Cafe")
        XCTAssertEqual(receipt.printedTotal, 17000)
        XCTAssertEqual(receipt.items.map(\.name), ["Coffee"])
        XCTAssertTrue(receipt.items[0].needsReview)
        XCTAssertFalse(receipt.reviewed)
        context.delete(receipt); try context.save()
    }
    @MainActor func testScannedChargesRequireSelection() throws {
        let storyboard = UIStoryboard(name: "Main", bundle: Bundle(for: AppDelegate.self))
        let context = (UIApplication.shared.delegate as! AppDelegate).container.mainContext
        let draft = ReceiptOCR.parse([("Lunch 100.00", 1), ("CGST 2.50", 1), ("SGST 2.50", 1)])
        let first = Receipt(merchant: "First"); context.insert(first)
        let review = try XCTUnwrap(storyboard.instantiateViewController(withIdentifier: "OCRReview") as? OCRReviewViewController)
        review.receipt = first; review.draft = draft; review.loadViewIfNeeded(); review.importItems()
        XCTAssertEqual(first.cgst, 0); XCTAssertEqual(first.sgst, 0)
        let second = Receipt(merchant: "Second"); context.insert(second)
        let review2 = try XCTUnwrap(storyboard.instantiateViewController(withIdentifier: "OCRReview") as? OCRReviewViewController)
        review2.receipt = second; review2.draft = draft; review2.loadViewIfNeeded()
        review2.tableView(review2.tableView, didSelectRowAt: IndexPath(row: 0, section: 3)); review2.importItems()
        XCTAssertEqual(second.cgst, 250); XCTAssertEqual(second.sgst, 0)
        context.delete(first); context.delete(second); try context.save()
    }
    func testOCRChargeCandidatesStaySeparateFromItems() {
        let draft = ReceiptOCR.parse([("Cafe", 1), ("Lunch 300.00", 1), ("CGST 2.5% 7.50", 0.9), ("SGST 2.5% 7.50", 0.9), ("Service Charge 15.00", 0.9), ("Discount -10.00", 0.9), ("Round off -0.50", 0.9), ("Grand Total 319.50", 1), ("CGST 2.5%", 1)])
        XCTAssertEqual(draft.lines.map(\.name), ["Lunch"])
        XCTAssertEqual(draft.charges.map(\.kind), [.cgst, .sgst, .service, .discount, .rounding])
        XCTAssertEqual(draft.charges.map(\.amount), [750, 750, 1500, 1000, -50])
        XCTAssertEqual(draft.total, 31950)
        XCTAssertTrue(draft.charges[0].source.contains("2.5%"))
    }
    func testOCRGroupsColumnsWithoutMergingAdjacentRows() {
        let rows = ReceiptOCR.groupRows([
            OCRTextBox(text: "Coffee", confidence: 0.9, bounds: CGRect(x: 0.1, y: 0.80, width: 0.3, height: 0.02)),
            OCRTextBox(text: "120.00", confidence: 0.8, bounds: CGRect(x: 0.8, y: 0.801, width: 0.1, height: 0.02)),
            OCRTextBox(text: "CGST", confidence: 0.95, bounds: CGRect(x: 0.1, y: 0.77, width: 0.2, height: 0.02)),
            OCRTextBox(text: "3.00", confidence: 0.9, bounds: CGRect(x: 0.8, y: 0.771, width: 0.1, height: 0.02))
        ])
        let draft = ReceiptOCR.parse(rows)
        XCTAssertEqual(draft.lines.map(\.name), ["Coffee"])
        XCTAssertEqual(draft.lines.first?.amount, 12000)
        XCTAssertEqual(draft.charges.first?.amount, 300)
        XCTAssertEqual(draft.charges.first?.kind, .cgst)
        XCTAssertEqual(rows.count, 2)
    }
    func testOCRParsesWholeNumberItemColumnsAndQuantity() {
        let draft = ReceiptOCR.parse([("Cafe", 1), ("Particulars Qty Rate Amount", 1), ("Potatoes 120 120", 1), ("Pizza (M) 300 300", 1), ("Cake 2 150 300", 1), ("Sub Total : 720.00", 1), ("CGST @2.5% : 18.00", 1), ("SGST @2.5% : 18.00", 1), ("Food Total : 756.00", 1)])
        XCTAssertEqual(draft.lines.map(\.name), ["Potatoes", "Pizza (M)", "Cake"])
        XCTAssertEqual(draft.lines.map(\.amount), [12000, 30000, 30000])
        XCTAssertEqual(draft.lines.last?.quantity, 2)
        XCTAssertEqual(draft.lines.last?.unitPrice, 15000)
        XCTAssertEqual(draft.charges.map(\.amount), [1800, 1800])
        XCTAssertEqual(draft.total, 75600)
    }
    func testOCRSupportsDifferentItemHeadingsAndClosesTableAtCharges() {
        for header in ["Description Qty Price Amount", "Dish Quantity Price", "Product Qty Total", "Menu Item Amount"] {
            let draft = ReceiptOCR.parse([("Cafe", 1), (header, 1), ("Dosa 1 120 120", 1), ("Tea 2 30 60", 1), ("CGST 4.50", 1), ("SGST 4.50", 1), ("Total 189.00", 1)])
            XCTAssertEqual(draft.lines.map(\.name), ["Dosa", "Tea"], header)
            XCTAssertEqual(draft.lines.map(\.amount), [12000, 6000], header)
            XCTAssertEqual(draft.lines.last?.quantity, 2, header)
            XCTAssertEqual(draft.charges.map(\.amount), [450, 450], header)
            XCTAssertEqual(draft.total, 18900, header)
        }
        let withoutHeading = ReceiptOCR.parse([("Cafe", 1), ("Coffee 120.00", 1), ("Total 120.00", 1)])
        XCTAssertEqual(withoutHeading.lines.map(\.name), ["Coffee"])
    }
    func testMoneyValidationAndExactParsing() {
        XCTAssertEqual(Money.parse("₹1,234.56"), 123456)
        XCTAssertEqual(Money.parse("0.01"), 1)
        XCTAssertEqual(Money.parse("-0.25", signed: true), -25)
        for value in ["", "1.234", "-1", "nan", "1e4", "10000001", "abc"] { XCTAssertNil(Money.parse(value), value) }
    }
    func testRemainderConservation() {
        XCTAssertEqual(SplitEngine.distribute(100, weights: [1, 1, 1]), [34, 33, 33])
        XCTAssertEqual(SplitEngine.distribute(-100, weights: [1, 1, 1]), [-34, -33, -33])
        for amount in -100...100 {
            let shares = SplitEngine.distribute(amount, weights: [1, 2, 3, 0])
            XCTAssertEqual(shares.reduce(0, +), amount)
            XCTAssertEqual(shares[3], 0)
        }
        XCTAssertEqual(SplitEngine.distribute(100, weights: [0, 0]), [0, 0])
    }
    func bill() -> Receipt {
        let receipt = Receipt(merchant: "Campus Cafe")
        receipt.people = [Participant(name: "Aryan", paid: 22000), Participant(name: "Aditya")]
        receipt.items = [ReceiptItem(name: "Lunch", quantity: 2, unitPrice: 10000)]
        receipt.cgst = 1000; receipt.sgst = 1000; receipt.printedTotal = 22000
        return receipt
    }
    func testEqualGSTAndSettlement() {
        let receipt = bill(), result = SplitEngine.calculate(receipt)
        XCTAssertTrue(result.issues.isEmpty)
        XCTAssertEqual(result.balances.map(\.owed).sorted(), [11000, 11000])
        XCTAssertEqual(result.transfers.count, 1)
        XCTAssertEqual(result.transfers.first?.from, "Aditya")
        XCTAssertEqual(result.transfers.first?.to, "Aryan")
        XCTAssertEqual(result.transfers.first?.amount, 11000)
        XCTAssertTrue(SplitEngine.summary(receipt).contains("CGST:"))
    }
    func testWeightedQuantityCustomAndPersonalSplits() {
        let receipt = bill(), item = receipt.items[0]
        let a = receipt.people[0].id.uuidString, b = receipt.people[1].id.uuidString
        item.splitMode = "weighted"; item.allocations = [a: 3, b: 1]
        var result = SplitEngine.calculate(receipt)
        XCTAssertEqual(result.balances.first { $0.name == "Aryan" }?.owed, 16500)
        item.splitMode = "quantity"; item.allocations = [a: 1, b: 1]
        XCTAssertTrue(SplitEngine.calculate(receipt).issues.isEmpty)
        item.allocations = [a: 2, b: 1]
        XCTAssertTrue(SplitEngine.calculate(receipt).issues.contains { $0.contains("quantities") })
        item.splitMode = "custom"; item.allocations = [a: 12000, b: 8000]
        result = SplitEngine.calculate(receipt)
        XCTAssertEqual(result.balances.first { $0.name == "Aryan" }?.owed, 13200)
        item.allocations = [a: 1]
        XCTAssertTrue(SplitEngine.calculate(receipt).issues.contains { $0.contains("Custom") })
        item.splitMode = "equal"; item.allocations = [a: 1, b: 0]
        XCTAssertEqual(SplitEngine.calculate(receipt).balances.first { $0.name == "Aryan" }?.owed, 22000)
        item.allocations = ["removed": 0]
        XCTAssertTrue(SplitEngine.calculate(receipt).issues.contains { $0.contains("Assign") })
    }
    func testDiscountTipRoundingAndMultiplePayers() {
        let receipt = bill()
        receipt.discount = 1001; receipt.tip = 500; receipt.rounding = -1
        receipt.printedTotal = receipt.total
        receipt.people[0].paid = 10000; receipt.people[1].paid = receipt.total - 10000
        let result = SplitEngine.calculate(receipt)
        XCTAssertTrue(result.issues.isEmpty)
        XCTAssertEqual(result.balances.reduce(0) { $0 + $1.owed }, receipt.total)
        XCTAssertEqual(result.balances.reduce(0) { $0 + $1.balance }, 0)
        XCTAssertEqual(result.transfers.reduce(0) { $0 + $1.amount }, abs(result.balances[0].balance))
    }
    func testReviewAndReconciliationGuards() {
        let receipt = bill()
        receipt.items[0].needsReview = true
        XCTAssertTrue(SplitEngine.calculate(receipt).issues.contains { $0.contains("scanned") })
        receipt.items[0].needsReview = false; receipt.printedTotal = nil
        XCTAssertFalse(receipt.isReconciled)
        XCTAssertTrue(SplitEngine.calculate(receipt).issues.contains { $0.contains("printed total") })
        receipt.printedTotal = receipt.total + 1
        XCTAssertEqual(receipt.difference, -1)
        XCTAssertTrue(SplitEngine.calculate(receipt).transfers.isEmpty)
        receipt.printedTotal = receipt.total; receipt.people[0].paid = 0
        XCTAssertTrue(SplitEngine.calculate(receipt).issues.contains { $0.contains("Payments") })
        receipt.discount = receipt.subtotal + 1
        XCTAssertTrue(SplitEngine.calculate(receipt).issues.contains { $0.contains("negative") })
        receipt.people = []
        XCTAssertEqual(SplitEngine.calculate(receipt).issues, ["Add at least one participant."])
    }
    @MainActor func testDiskPersistenceUpdatesAndCascadeDelete() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".store")
        // SwiftData can retain SQLite handles after a container is released.
        // Leave this unique file in the test app's temporary directory for OS cleanup.
        let config = ModelConfiguration(url: url)
        var container: ModelContainer? = try ModelContainer(for: Receipt.self, ReceiptItem.self, Participant.self, configurations: config)
        let receipt = bill(); receipt.items[0].allocations = [receipt.people[0].id.uuidString: 2]
        container!.mainContext.insert(receipt); try container!.mainContext.save()
        let id = receipt.id
        receipt.merchant = "Updated Cafe"; receipt.people[0].name = "Updated Aryan"
        try container!.mainContext.save(); container = nil
        let reopened = try ModelContainer(for: Receipt.self, ReceiptItem.self, Participant.self, configurations: config)
        let records = try reopened.mainContext.fetch(FetchDescriptor<Receipt>())
        XCTAssertEqual(records.count, 1); XCTAssertEqual(records[0].id, id)
        XCTAssertEqual(records[0].merchant, "Updated Cafe")
        XCTAssertEqual(records[0].items.count, 1); XCTAssertEqual(records[0].people.count, 2)
        XCTAssertEqual(records[0].items[0].allocations.values.first, 2)
        reopened.mainContext.delete(records[0]); try reopened.mainContext.save()
        XCTAssertTrue(try reopened.mainContext.fetch(FetchDescriptor<Receipt>()).isEmpty)
        XCTAssertTrue(try reopened.mainContext.fetch(FetchDescriptor<ReceiptItem>()).isEmpty)
        XCTAssertTrue(try reopened.mainContext.fetch(FetchDescriptor<Participant>()).isEmpty)
    }
    func testOCRParserKeepsAdjustmentsOutOfItems() {
        let draft = ReceiptOCR.parse([("Campus Cafe", 0.99), ("Coffee 120.00", 0.9), ("Sandwich 200.00", 0.6), ("Subtotal 320.00", 0.9), ("CGST 8.00", 0.9), ("SGST 8.00", 0.9), ("Grand total 336.00", 0.9)])
        XCTAssertEqual(draft.merchant, "Campus Cafe")
        XCTAssertEqual(draft.lines.map(\.amount), [12000, 20000])
        XCTAssertEqual(draft.total, 33600)
        XCTAssertEqual(draft.lines[1].confidence, 0.6)
    }
    @MainActor func testVisionRecognizesReceiptImage() async throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1000, height: 700))
        let image = renderer.image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 1000, height: 700))
            let style: [NSAttributedString.Key: Any] = [.font: UIFont.monospacedSystemFont(ofSize: 44, weight: .medium), .foregroundColor: UIColor.black]
            for (i, line) in ["Campus Cafe", "Coffee 120.00", "Sandwich 200.00", "TOTAL 320.00"].enumerated() {
                (line as NSString).draw(at: CGPoint(x: 60, y: 60 + i * 110), withAttributes: style)
            }
        }
        let draft = try await ReceiptOCR.recognize([image])
        XCTAssertTrue(draft.rawText.contains("Coffee"), draft.rawText)
        XCTAssertEqual(draft.total, 32000, draft.rawText)
        XCTAssertEqual(draft.lines.reduce(0) { $0 + $1.amount }, 32000, draft.rawText)
    }
}
