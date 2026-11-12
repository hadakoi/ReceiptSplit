# ReceiptSplit — UIKit and Storyboards

This is the storyboard-based iPhone version of ReceiptSplit for the iOS lab. If you also have the earlier SwiftUI project, it uses a separate bundle identifier and local storage.

Open `ReceiptSplit.xcodeproj` in Xcode and select **Main.storyboard** to inspect the navigation controller, eight screen scenes, segues, headers and reusable cells. Expand a scene's Table View in the document outline to edit its header and `Symbol-…` prototype cells, including their icons, colors, labels and constraints. Receipt and participant values are supplied by the corresponding `UITableViewController` classes, which choose a prototype for each row. `StoryboardSupport.swift` connects the storyboard cell outlets to dynamic content and editing. `UIKitApp.swift` starts the storyboard using the UIKit scene lifecycle.

Select the ReceiptSplit scheme and an iPhone simulator, then press Run. For a physical iPhone, select your Apple development team in Signing & Capabilities and follow Xcode’s device setup prompts. The minimum supported iOS version is 17.

Tap **Scan a receipt** on the home screen to scan a new bill. You can also tap **+** to scan, import a photo, or enter the receipt manually. Review the detected items and charges before importing; canceling the scan does not create a receipt. Then add people, assign items and record who paid the merchant.

For halves, thirds or quarters, choose Equal and select two, three or four people. For unequal fractions, choose Weighted: 1:2 gives one third and two thirds, and 1:3 gives one quarter and three quarters. Check suggested charges against the bill and enter missing values manually.

## Features

- Create, read, edit, search, and delete receipts; edit line items and participants; record multiple payments.
- Split each item equally among everyone or selected people, by whole quantities, by weights, or by custom amounts.
- Enter CGST, SGST, service charge, tip, discount, rounding, and the printed total. Review reconciliation and a person-wise settlement before sharing.
- Scan on a supported iPhone or select a photo, use on-device Vision OCR, select detected rows, and review every imported item. Recognizable CGST, SGST, service charge, discount, rounding and tip lines are offered as optional suggestions; check each against the receipt. Unusual layouts and missing charges may require manual entry.
- Store receipts locally with SwiftData. Amounts use integer paise and allocation uses largest-remainder rounding. No account, payment integration, or cloud OCR is required.

Amounts for inclusive taxes should not be added again. Adjustments are distributed in proportion to item subtotals. Payment totals and the calculated receipt total must match before confirmation. Participants belong to individual receipts; reusable groups are not implemented.

## Tests

Choose **Product → Test** in Xcode. The unit suite checks monetary parsing, allocation, adjustments, reconciliation, multiple payers, disk persistence, cascade deletion, the OCR parser, and Vision recognition of a generated image. UI tests exercise receipt, item, and participant editing, deletion, settlement review, cancellation, and validation. UI tests use a separate in-memory store.

For a command-line run, choose an installed simulator and use:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project ReceiptSplit.xcodeproj -scheme ReceiptSplit \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.0' \
  -derivedDataPath .build CODE_SIGNING_ALLOWED=NO test
```

`generate_project.py` is a helper for maintaining the Xcode project’s file references; do not use it to edit or regenerate the storyboard.
