# PDF Export Layout (Page by Page / Continuous) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Layout choice — Page by Page (paginated, default) or Continuous (today's single long page) — to the ⌘E PDF export save panel, persisted across exports.

**Architecture:** The choice lives in an `NSSavePanel` accessory view built in `MarkdownWebView.Coordinator`. The export flow inverts from render-then-ask to ask-then-render: panel first, then `beforeExport()` JS, then either the existing `WKWebView.createPDF` path (continuous) or a headless `NSPrintOperation` from `webView.printOperation(with:)` (page by page), then `afterExport()`. Persistence is a new `ExportLayout` enum + `Settings` key, mirroring how `ReadingTheme` is stored.

**Tech Stack:** Swift 6.2 / SwiftUI + AppKit, WKWebView, XCTest. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-08-11-pdf-export-layout-design.md`

## Global Constraints

- Deployment target is **macOS 13.0**; any newer API needs `#available` with a fallback. `WKPreferences.shouldPrintBackgrounds` is **13.3+** — guard it; on 13.0–13.2 paginated export prints on white (accepted, no workaround).
- Build with `swift build` / test with `swift test` (Xcode 26 / Swift 6.2 toolchain). UI behavior is verified by running the app (`swift run ReaderMd`) — the test target is pure logic only.
- Exact copy: menu shows **"Page by Page"** and **"Continuous"**; the accessory label is **"Layout:"**. Default and fallback are always page-by-page.
- Paper size/margins: system default via a fresh `NSPrintInfo()` — no picker, no hard-coded size. No headers/footers/page numbers.
- The app is the single writer of its own preferences; the `reader` CLI is untouched by this feature.
- Commit messages: conventional style (`feat:`/`docs:`/`test:`), imperative subject, no Co-Authored-By or generated-with footers (repo convention).

---

### Task 1: `ExportLayout` enum + Settings persistence

**Files:**
- Modify: `Sources/ReaderMd/Models/AppState.swift` (add enum after `ContentWidth`, which ends at line ~96)
- Modify: `Sources/ReaderMd/Models/Settings.swift` (key at line ~20 block, load/save after the reading-theme pair at line ~53-58)
- Test: `Tests/ReaderMdTests/ExportLayoutTests.swift` (create)

**Interfaces:**
- Consumes: nothing new.
- Produces: `enum ExportLayout: String, CaseIterable` with cases `.pageByPage`, `.continuous`, `var displayName: String`, `static func named(_ raw: String?) -> ExportLayout`; `Settings.loadExportLayout() -> ExportLayout` and `Settings.saveExportLayout(_ value: ExportLayout)`. Task 3 depends on all of these, and on `allCases` order being `[.pageByPage, .continuous]` (it indexes the popup by `allCases`).

- [ ] **Step 1: Write the failing test**

Create `Tests/ReaderMdTests/ExportLayoutTests.swift`, mirroring the style of `ReadingThemeTests.swift`:

```swift
import XCTest
@testable import ReaderMd

/// The export-layout resolver must never fail closed: an absent or
/// unrecognized persisted value falls back to page-by-page, the default.
final class ExportLayoutTests: XCTestCase {

    func testKnownNamesResolve() {
        XCTAssertEqual(ExportLayout.named("pageByPage"), .pageByPage)
        XCTAssertEqual(ExportLayout.named("continuous"), .continuous)
    }

    func testNilFallsBackToPageByPage() {
        XCTAssertEqual(ExportLayout.named(nil), .pageByPage)
    }

    func testUnknownNameFallsBackToPageByPage() {
        XCTAssertEqual(ExportLayout.named("nonexistent"), .pageByPage)
        XCTAssertEqual(ExportLayout.named(""), .pageByPage)
    }

    /// Order matters — it's the order the save panel's layout popup offers,
    /// and the popup is indexed by allCases.
    func testCaseIterableOrder() {
        XCTAssertEqual(ExportLayout.allCases, [.pageByPage, .continuous])
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter ExportLayoutTests`
Expected: **compile error** — `cannot find 'ExportLayout' in scope`. (A compile failure is this step's "failing test".)

- [ ] **Step 3: Implement the enum and Settings pair**

In `Sources/ReaderMd/Models/AppState.swift`, directly after the closing brace of `enum ContentWidth` (~line 96):

```swift
/// How ⌘E lays out the PDF: real pages via the print engine, or one
/// continuous page the height of the whole document.
enum ExportLayout: String, CaseIterable {
    case pageByPage, continuous

    var displayName: String {
        switch self {
        case .pageByPage: return "Page by Page"
        case .continuous: return "Continuous"
        }
    }

    /// Absent or unrecognized persisted values fall back to the default.
    static func named(_ raw: String?) -> ExportLayout {
        raw.flatMap(ExportLayout.init(rawValue:)) ?? .pageByPage
    }
}
```

In `Sources/ReaderMd/Models/Settings.swift`, add to the key block (after `editorBundleIDKey`, ~line 20):

```swift
    private static let exportLayoutKey = "reader.md.exportLayout"
```

and after the reading-theme load/save pair (~line 58):

```swift
    // Export
    static func loadExportLayout() -> ExportLayout {
        ExportLayout.named(defaults.string(forKey: exportLayoutKey))
    }
    static func saveExportLayout(_ value: ExportLayout) {
        defaults.set(value.rawValue, forKey: exportLayoutKey)
    }
```

No `@Published` on `AppState` — nothing observes the value; the coordinator reads it when the panel opens and writes it on OK.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter ExportLayoutTests`
Expected: `Executed 4 tests, with 0 failures`. Then run the full suite: `swift test` — all pass (232 existing + 4).

- [ ] **Step 5: Commit**

```bash
git add Sources/ReaderMd/Models/AppState.swift Sources/ReaderMd/Models/Settings.swift Tests/ReaderMdTests/ExportLayoutTests.swift
git commit -m "feat: add ExportLayout enum with page-by-page default"
```

---

### Task 2: Print CSS in the web template

**Files:**
- Modify: `Sources/ReaderMd/Resources/web/template.html` (inside the `<style>` block; put the new rules at the end of it, after the `mark.rmd-highlight` rules ~line 160)

**Interfaces:**
- Consumes: existing selectors — `.markdown-body` (the reading column, `max-width: var(--content-width)`), `.mermaid` (diagram wrapper), `.mm-controls` (diagram zoom buttons), `.copy-btn` (code-copy button), `.anchor` (heading hover anchor).
- Produces: print behavior only; no selector or API any other task references.

- [ ] **Step 1: Add the `@media print` block**

```css
    /* ⌘E page-by-page export renders through the print engine. Pages bring
       their own width, so the canvas cap comes off; diagrams and images must
       not be sawn in half at a page boundary; hover-only chrome (zoom
       controls, copy buttons, heading anchors) is hidden outright rather
       than trusted to be un-hovered. */
    @media print {
      .markdown-body { max-width: none; }
      .mermaid, img { break-inside: avoid; }
      .mm-controls, .copy-btn, .anchor { display: none; }
    }
```

Continuous export via `createPDF` uses screen media, so this block is inert for it — the continuous path's output is unchanged.

- [ ] **Step 2: Verify the app still renders**

Run: `swift build && swift test`
Expected: build succeeds, all tests pass (the template ships as a bundled resource; a CSS typo can't fail the build, so real verification happens in Task 3's manual check — this step only guards against accidental damage to the file).

- [ ] **Step 3: Commit**

```bash
git add Sources/ReaderMd/Resources/web/template.html
git commit -m "feat: add print CSS for paginated PDF export"
```

---

### Task 3: Export flow — panel first, layout accessory, paginated path

**Files:**
- Modify: `Sources/ReaderMd/Views/MarkdownWebView.swift`
  - `makeNSView` (~line 82, right after `let config = WKWebViewConfiguration()`)
  - the `// MARK: Export` section of `Coordinator` (~lines 463–497: `exportPDF()`, `generatePDF()`, `savePDF(_:)`)

**Interfaces:**
- Consumes: `ExportLayout`, `Settings.loadExportLayout()`, `Settings.saveExportLayout(_:)` from Task 1; print CSS from Task 2.
- Produces: user-visible behavior only. `exportPDF()` keeps its name and zero-argument signature — the `updateNSView` trigger at line ~171 (`coord.exportPDF()` on `exportToken` change) is untouched. `generatePDF()` and `savePDF(_:)` are **deleted** (replaced by `exportContinuous(to:)` / `exportPaginated(to:)`); nothing else in the codebase calls them (verify with `grep -rn "generatePDF\|savePDF" Sources/`).

- [ ] **Step 1: Enable print backgrounds on the web view configuration**

In `makeNSView`, immediately after `let config = WKWebViewConfiguration()` (line ~82):

```swift
        // Paginated ⌘E export prints; printing drops CSS backgrounds unless
        // asked not to. 13.3+ only — on 13.0–13.2 page-by-page exports print
        // on white, accepted per the design spec.
        if #available(macOS 13.3, *) {
            config.preferences.shouldPrintBackgrounds = true
        }
```

- [ ] **Step 2: Replace the export section of `Coordinator`**

Replace the whole block from `func exportPDF() {` through the end of `savePDF(_:)` (currently ~lines 465–497) with:

```swift
        func exportPDF() {
            guard let webView else { return }

            // Panel first (it now carries the layout choice), render after.
            // Cancel ends here — beforeExport() hasn't run, nothing to restore.
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.pdf]
            let base = (loadedPath as NSString?)?.lastPathComponent ?? "document"
            panel.nameFieldStringValue = (base as NSString).deletingPathExtension + ".pdf"

            let picker = NSPopUpButton(frame: .zero, pullsDown: false)
            picker.addItems(withTitles: ExportLayout.allCases.map(\.displayName))
            picker.selectItem(at: ExportLayout.allCases.firstIndex(of: Settings.loadExportLayout()) ?? 0)
            let row = NSStackView(views: [NSTextField(labelWithString: "Layout:"), picker])
            row.orientation = .horizontal
            row.edgeInsets = NSEdgeInsets(top: 10, left: 0, bottom: 10, right: 0)
            panel.accessoryView = row

            guard panel.runModal() == .OK, let url = panel.url else { return }
            let layout = ExportLayout.allCases[picker.indexOfSelectedItem]
            Settings.saveExportLayout(layout)

            // Find highlights and diagram zoom would both bake into the PDF.
            // beforeExport() resets them; wait for that JS to finish, render,
            // then afterExport() puts them back. Both halves no-op when nothing
            // is active, so there is no state to branch on here.
            webView.evaluateJavaScript("window.ReaderMd.beforeExport();") { [weak self] _, _ in
                switch layout {
                case .continuous: self?.exportContinuous(to: url)
                case .pageByPage: self?.exportPaginated(to: url)
                }
            }
        }

        private func exportContinuous(to url: URL) {
            guard let webView else { return }
            webView.createPDF(configuration: WKPDFConfiguration()) { [weak self] result in
                // afterExport() restores the exact find match the user was on;
                // find() would scroll them back to match 1 as a side effect of
                // exporting.
                self?.webView?.evaluateJavaScript("window.ReaderMd.afterExport();")
                guard case let .success(data) = result else { return }
                try? data.write(to: url)
            }
        }

        private func exportPaginated(to url: URL) {
            guard let webView, let window = webView.window else { return }
            let info = NSPrintInfo()   // copies the shared defaults: system paper size + margins
            info.jobDisposition = .save
            info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url

            let op = webView.printOperation(with: info)
            op.showsPrintPanel = false
            op.showsProgressPanel = false
            // WKWebView's print view starts zero-sized and prints blank pages
            // unless given a frame before the run.
            op.view?.frame = webView.bounds
            // WKWebView print operations only work through runModal(for:...) —
            // a bare run() silently produces nothing. Panels are hidden, so
            // nothing modal is actually shown.
            op.runModal(for: window, delegate: self,
                        didRun: #selector(printOperationDidRun(_:success:contextInfo:)),
                        contextInfo: nil)
        }

        @objc private func printOperationDidRun(_ printOperation: NSPrintOperation,
                                                success: Bool,
                                                contextInfo: UnsafeMutableRawPointer?) {
            webView?.evaluateJavaScript("window.ReaderMd.afterExport();")
        }
```

Notes for the implementer:
- `Coordinator` is already an `NSObject` subclass (it conforms to `WKScriptMessageHandler`), so the `@objc` selector works as-is.
- `evaluateJavaScript` completion handlers run on the main thread; the coordinator is `@MainActor`. If the compiler still rejects the `switch` inside the completion under strict concurrency, wrap the completion body in `Task { @MainActor in … }`.
- Do not touch `updateNSView`'s `exportToken` handling or the `encode(_:)` helper below the export section.

- [ ] **Step 3: Build and run the full test suite**

Run: `swift build && swift test`
Expected: build succeeds; all tests pass (nothing in the test target touches the coordinator).

- [ ] **Step 4: Verify manually in the running app**

Run: `swift run ReaderMd`, open a long markdown file that contains code blocks, a wide table, at least one image, and a Mermaid diagram (e.g. this repo's `docs/superpowers/plans/2026-07-27-markdown-diff-mode.md` or any long doc). Then:

1. ⌘E → save dialog shows **Layout:** popup, preset to **Page by Page**.
2. Export with Page by Page → open the PDF in Preview: multiple paper-size pages; no diagram or image cut across a page boundary; theme background present (on macOS 13.3+); no zoom/copy buttons visible.
3. ⌘E again → popup now remembers the last choice; switch to **Continuous**, export → one long single page, identical to pre-change output.
4. ⌘E → Cancel → document view unaffected (find highlights/diagram zoom, if any, still intact — beforeExport never ran).
5. With an active ⌘F search and a zoomed diagram, export Page by Page → PDF has no highlight boxes or zoomed diagram; after export the app restores the current find match and zoom.
6. Toggle dark mode and re-export Page by Page → dark background in the PDF (13.3+).

Expected: all six pass. If pages come out blank in step 2, re-check the `op.view?.frame = webView.bounds` line — that is the known WKWebView print pitfall.

- [ ] **Step 5: Commit**

```bash
git add Sources/ReaderMd/Views/MarkdownWebView.swift
git commit -m "feat: page-by-page/continuous layout choice in PDF export

The ⌘E save panel gains a Layout popup (page-by-page default, last
choice persisted). Page-by-page renders through WebKit's print engine
via NSPrintOperation — real page breaks, system paper size, backgrounds
kept on 13.3+ — while continuous keeps the existing createPDF path. The
flow inverts to panel-first so the choice exists before rendering."
```

---

### Task 4: Documentation and site data

**Files:**
- Modify: `Sources/ReaderMd/Resources/docs/FAQ.md` (~line 65, the export answer)
- Modify: `Sources/ReaderMd/Resources/docs/CHANGELOG.md` (the `## [Unreleased]` section, ~line 7)
- Modify: `docs/features.md` (line 25, the export bullet)
- Modify: `web/src/data/content.ts` (~line 114, the "Live reload & export" feature row)

**Interfaces:**
- Consumes: final UI copy from Task 3 ("Layout:", "Page by Page", "Continuous").
- Produces: nothing other tasks use.

- [ ] **Step 1: Update the bundled FAQ**

Replace:

```markdown
**How do I export to PDF?**
**File → Export as PDF…** (⌘E) renders the current document to PDF.
```

with:

```markdown
**How do I export to PDF?**
**File → Export as PDF…** (⌘E) renders the current document to PDF. A **Layout**
control in the save dialog picks **Page by Page** — real pages at your system
paper size, the default — or **Continuous**, one long page. The last choice is
remembered.
```

- [ ] **Step 2: Add the changelog entry**

In `Sources/ReaderMd/Resources/docs/CHANGELOG.md`, the `## [Unreleased]` section currently has a `### Changed` block. Insert an `### Added` block **above** it (Keep a Changelog order):

```markdown
### Added

- **Page-by-page PDF export.** The ⌘E save dialog now has a Layout control:
  **Page by Page** (the default) paginates the document onto real pages at your
  system paper size, with diagrams and images kept whole across page breaks;
  **Continuous** keeps the old single long page. Your last choice is remembered.
```

- [ ] **Step 3: Update `docs/features.md`**

Replace line 25:

```markdown
- **Export to PDF** (⌘E) and **manual reload** (⌘R) — toolbar buttons on the right, plus the web view's native PDF renderer
```

with:

```markdown
- **Export to PDF** (⌘E) and **manual reload** (⌘R) — toolbar buttons on the right; the save dialog's Layout control picks page-by-page (default) or one continuous page, and remembers the choice
```

- [ ] **Step 4: Mirror to the site data**

In `web/src/data/content.ts` (~line 114), replace the "Live reload & export" row's body:

```ts
    body: "The open file re-renders (scroll preserved) and the tree refreshes on disk changes. Export to PDF (⌘E), manual reload (⌘R), and Sparkle auto-update.",
```

with:

```ts
    body: "The open file re-renders (scroll preserved) and the tree refreshes on disk changes. Export to PDF (⌘E) — page-by-page or continuous — manual reload (⌘R), and Sparkle auto-update.",
```

Do **not** touch `web/src/data/changelog.ts` — the site changelog is per release, not per merge.

- [ ] **Step 5: Verify the site builds**

Run: `cd web && npm run build`
Expected: `[build] Complete!` with no type errors.

- [ ] **Step 6: Commit**

```bash
git add Sources/ReaderMd/Resources/docs/FAQ.md Sources/ReaderMd/Resources/docs/CHANGELOG.md docs/features.md web/src/data/content.ts
git commit -m "docs: describe the PDF export layout choice"
```

Note: pushing this commit to `main` deploys the site (it touches `web/`), so it should land together with — not ahead of — the release that ships the feature.
