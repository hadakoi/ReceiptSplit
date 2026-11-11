# Storyboard verification

Verified on November 11, 2026 with Xcode and the iPhone 18 Pro simulator running iOS 27.0.

Xcode's test navigator shows all **10 unit tests and 3 UI tests passing**. The UI results came from a full suite run and a subsequent rerun of the edit/delete test after correcting its simulated text selection. The unit tests cover currency parsing, split methods, rounding, adjustments, multiple payers, reconciliation, disk persistence, cascade deletion, OCR parsing, generated-image Vision recognition, storyboard scene creation, and OCR review/import. The UI tests cover receipt, item, and participant CRUD, validation and cancellation, equal settlement, and weighted and custom allocations.

A separate hands-on simulator check launched the app with Xcode's Run button, created a ₹20 receipt, added Alex and Sam, recorded Alex's ₹20 payment, and confirmed the equal settlement showed Sam paying Alex ₹10. Confirming the review displayed the share action, and its iOS share sheet opened. This sample remains in the storyboard app's simulator storage.

Camera capture on a physical iPhone, photo-picker behavior with varied real receipts, delivery to an external share destination, VoiceOver, and device performance still require manual checks. The OCR engine is heuristic; verify all recognized fields and amounts. The earlier test-runner startup on the iOS 27.2 simulator stalled, so the passing results above use the initialized iOS 27.0 simulator.
