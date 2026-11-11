# ReceiptSplit implementation plan

## Goal

Build the iPhone workflow: **scan → review automatically extracted items and charges → add people → assign item shares → reconcile and settle**. Keep the screens in UIKit and `Main.storyboard`, work offline, and let the user correct every detected value. The existing SwiftData receipts must remain readable.

This document is a plan; the automatic charge extraction and revised workflow below are not implemented yet.

## Current starting point

- `OCRService.swift` uses Vision on-device. It currently recognizes item-like lines ending in decimal amounts, suggests a merchant and printed total, and excludes tax, discount, service and rounding lines instead of extracting them.
- `Models.swift` stores receipt items, participants, payments, CGST, SGST, service charge, tip, discount, rounding and an optional printed total in integer paise. The receipt editor already accepts these adjustment amounts manually.
- `SplitEngine.swift` supports equal, quantity, weighted and custom allocations, proportional adjustment sharing, payment balances and paise-preserving rounding. It currently uses one calculated total for both reconciliation and settlement.
- The storyboard app has receipt, item and participant editing, scan review, settlement and sharing. The scan review does not yet expose extracted charges or guide the entire workflow in the requested order.

## Product workflow

1. **Scan or enter manually.** From the receipt list, start with the camera, a photo, or a blank receipt. Run Vision on-device; support multiple pages and allow cancellation without saving a partial receipt.
2. **Review the extracted receipt.** Show the merchant, date if reliably detected, item rows, quantities and amounts, subtotal, CGST, SGST, service charge, discount, rounding and printed total. Keep the raw recognized text accessible. Show the source text and confidence or an uncertainty indicator for suggestions. Let the user edit, add, remove or reclassify any row, including missed charges. Do not accept a guess silently.
3. **Add people and payments.** Add or edit participants and record each person's payment to the merchant. Allow multiple payers and validate names and amounts. Make it clear the payment is separate from the person's share.
4. **Assign item shares.** For each item, select people and support equal shares, quantities, weights and exact amounts. Provide convenient half, third and quarter options, including an uneven allocation such as one quarter versus three quarters. Display each person's amount and any unassigned remainder; require the whole item to be allocated before settlement. A single person can take an entire item.
5. **Reconcile and settle.** Show the calculated bill, the printed total, the difference, each person's item and adjustment shares, payments, and proposed transfers. Explain any unresolved issue and link back to the relevant edit screen. Confirm review before sharing; invalidate confirmation after a material edit.

## Extracting receipt fields

- Extend the OCR draft with typed candidates for merchant, date, subtotal, item rows, CGST, SGST, service charge, discount, rounding, tip and grand total. Retain source text, page/line position, Vision confidence, parser confidence or reason, and whether the user confirmed, changed or rejected each suggestion.
- Group recognized text using bounding boxes so labels and amounts in separate columns can be associated. Support common Indian receipt labels and variations, such as `CGST`, `C GST`, `SGST`, `service charge`, `svc charge`, `discount`, `disc`, `round off`, `rounding`, `subtotal`, `grand total`, and `net payable`. Treat a generic `GST` line as an unclassified tax suggestion unless the receipt supports a more specific classification.
- Parse `₹`, `Rs` and `INR` prefixes, comma-grouped amounts, integer and decimal prices, negative signs, parentheses and common discount/rounding formats. Distinguish a percentage from its currency amount: a line containing `CGST 2.5% 12.50` suggests ₹12.50, not ₹2.50. If a label has only a rate, do not invent an amount or taxable base; show it for review and let the user provide the base and amount.
- Distinguish subtotal from final total; detect conflicting totals, duplicate labels, multi-page repeats, low-confidence text and totals that do not reconcile. Present conflicts for the user to resolve instead of silently adding duplicates or selecting an arbitrary total. Keep a detected line from appearing both as an item and as an adjustment.
- Extract quantities and unit prices only when the receipt provides enough evidence. Otherwise import the detected line total as quantity one and flag it for review. Avoid silently deriving a unit price that changes the line total through rounding.
- The app cannot infer an amount or charge that is absent from the printed or visible receipt. Let the user add a named charge, discount, tip or rounding adjustment manually and label it as user-entered. Do not claim it was detected.

## Charge semantics and reconciliation

- Treat a discount as a non-negative deduction; retain signed rounding. Define how each adjustment affects the sum in the UI, and store money in paise. Do not guess that a signed discount is a positive charge.
- Handle inclusive taxes explicitly. Let the user mark tax as **included in item prices** or **added on top**; included amounts remain visible for explanation but are not added twice. If OCR cannot tell which applies, flag it for review. Support mixed or ambiguous cases through explicit editing rather than assuming every item has the same tax treatment.
- Distinguish **receipt adjustments** already reflected in the bill's printed grand total from **extra group adjustments** added after the bill was issued. First reconcile the printed total against items plus receipt adjustments. Then show a separate settlement total after any extra adjustments. An extra tip entered later should change the settlement total without falsely claiming the printed bill is incorrect. Make the category visible and editable for every manual adjustment.
- If a user supplies a percentage instead of an amount, require an explicit base and preview the calculated amount before saving; don't assume whether tax applies before or after discounts or service charges. The exact charge amount remains editable. Do not compute an absent amount from a rate unless the user confirms the base and resulting amount.
- Preserve the existing default: allocate shared receipt adjustments proportionally to each person's item subtotal, with a documented equal fallback when the subtotal is zero. Show this rule and the resulting per-person adjustments. Consider per-adjustment allocation controls only if needed to accurately represent the receipt; never imply that this default automatically models every restaurant's tax rules.
- Reconcile to the paise with a visible signed difference. Block final confirmation if the printed total is missing or inconsistent, an item is unreviewed or partly assigned, an adjustment is ambiguous, a share is negative, or recorded payments do not equal the settlement total. Permit drafts and corrections without requiring every field to be complete.
- Keep the receipt currency INR for this project. Store all calculations as integer paise, use deterministic largest-remainder allocation, and check for overflow and invalid input. State which total is used for the payment check and for transfers.

## Implementation sequence

1. **Models and compatibility.** Design typed draft candidates and charge origin/treatment/category fields. Add a SwiftData migration or a backward-compatible representation; preserve existing receipts, assignments and confirmation state safely. Ensure a changed receipt cannot retain a stale confirmation.
2. **Parser.** Separate recognition, line grouping and deterministic parsing so they can be tested independently. Implement field classification, amount/rate parsing, confidence and conflict reporting, and subtotal/total identification. Keep the original text available.
3. **Storyboard review screens.** Update `Main.storyboard` and the UIKit controllers to present editable items and charges, source/confidence, included-versus-added treatment and manual additions. Provide useful empty, ambiguous and no-camera states. Keep the existing manual-entry path usable.
4. **Participants and shares.** Refine the storyboard flow between review, participants and per-item assignment; add visible fraction presets and remainder validation while retaining existing equal, quantity, weighted and custom methods.
5. **Reconciliation and export.** Separate printed-bill reconciliation from the final settlement total, implement the chosen charge rules in the split engine, display per-person calculation details and improve the share summary. Show errors without losing edits.
6. **Verify and refine.** Run automated tests and inspect the full flow in Xcode's iPhone simulator. When the physical iPhone is available, install the app through Xcode and test scanning real paper receipts, including permissions and corrections; record observed results without claiming OCR is perfect.

## Acceptance checks

- A fixture with items ₹100 and ₹200, CGST ₹7.50, SGST ₹7.50, service ₹15, discount ₹10 and rounding −₹0.50 produces a printed total of **₹319.50**. The review screen shows each candidate, its source and editable amount; none of the charges appears as an item.
- A receipt with tax already included in a ₹200 item remains ₹200 when the user marks the tax included. Changing it to an added ₹10 tax makes the bill ₹210; the app never adds the same tax twice.
- A printed ₹200 bill can have a user-entered extra ₹20 tip: receipt reconciliation remains ₹200, settlement becomes ₹220, and the payment check uses ₹220.
- A charge absent from OCR can be added manually, edited and removed. Missing, rate-only, duplicate and conflicting tax lines are marked for review rather than silently accepted. Unknown charges are not fabricated.
- A ₹120 item can be split equally across two, three or four people, as well as 1:3 between two people; custom amounts and quantities are validated, and every paise is allocated. The app reports unassigned or over-assigned items before settlement.
- Reopening an existing saved receipt preserves its items, participants and payments after the data-model update. Canceling a scan or editor leaves saved data untouched. Edits after confirmation require a new review.
- Automated parser tests cover multiple-column layouts, label variants, integer/decimal/negative amounts, rates, inclusive tax ambiguity, duplicates, low confidence, multi-page receipts and mismatched totals. Calculation tests cover signed rounding, discounts, extra charges, exact allocation and multiple payers. UI tests cover the entire review-to-settlement workflow and error correction.
- On a physical iPhone, verify a clear receipt, a skewed or low-light receipt, multiple pages, a receipt with missing charges, and a tax-inclusive receipt; check camera permission denial, cancellation and manual corrections. Record successes, misses and device/iOS details. Real-camera testing remains pending until the phone is available.
