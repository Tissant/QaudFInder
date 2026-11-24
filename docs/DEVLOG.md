# QaudFInder Development Log

**English** | [한국어](DEVLOG.ko.md)

> **QaudFInder** — a lightweight macOS file manager that splits one window into 2×2 panes, each showing a different folder.
> Built in November 2026 · Planning & testing: Tissant · Implementation: Claude Code

---

## 1. At a glance

| | |
|---|---|
| Goal | A lightweight Finder alternative: four folders in one window |
| Tech | Swift + SwiftUI; file lists use AppKit (`NSOutlineView`, `NSCollectionView`) |
| Dependencies | **None** (Apple frameworks only) |
| App size | ~**1.8 MB** |
| Code | 15 Swift files + 2 tools, ~3,600 lines |
| Requirements | macOS 27.2 or later |
| Name | `QaudFInder` — originally a typo of *QuadFinder*, kept on purpose as a small mark of distinction |

### Principles we kept throughout

1. **One version at a time** — finish a version, test it by hand, and move on only after it passes.
2. **Build every change** — run `xcodebuild` after every edit and hand over only warning-free builds.
3. **Safety first** — files are only ever **moved to the Trash**; there is no permanent-delete code at all. Tests that change real files run only inside a dedicated test folder.
4. **Stay light** — no third-party packages; UI icons are SF Symbols.
5. **Git history** — a commit per version so anything can be rolled back.

---

## 2. Overall flow

```
[claude.ai chat]  v1 – v2  ──▶  hand-off document
                                   │
[Claude Code]     setup → v3 → v4 → v5 → v6 → icon · windows · installer → v7 → GitHub → 1.1.0
```

| Step | Contents |
|---|---|
| v2 | 2×2 split, view modes, Quick Look, copy between panes, merging (built in chat) |
| v3 | AppKit lists, multi-file drag, keyboard, sorting, active pane |
| v4 | File operations, folder size in the status bar |
| v5 | Sidebar & favorites, Go to Folder, `⌥`-drop to open a folder |
| v6 | Background copying, auto-refresh, hidden files |
| Wrap-up | App icon, new windows open at default folders, install script |
| v7 | File previews, expandable folders in list view, icon size slider |
| 1.1.0 | Open With & Services, path input, favorites cleanup, grid spacing, Settings window & custom shortcuts |

---

## 3. Version by version

### Step 0. Hand-off and setup (claude.ai chat → Claude Code)

- v2 (a single `ContentView.swift`, ~770 lines) was handed over with a hand-off document.
- Work rules, explanation style and the merge spec were moved into Claude Code's instruction file, so every new session reads them automatically.
- Confirmed the project uses **folder-synchronized groups**: any `.swift` file created under `QaudFInder/` is added to the Xcode target automatically.
- **Decision:** keep selecting panes to merge with `⌘`-click on the top bar.

### v3. New list architecture, selection & keyboard

**Why:** in v2, SwiftUI `List` selection conflicted with dragging on macOS, so the list was drawn by hand — which cost us *multi-file drag* and *drag-to-select*. Switching to the same AppKit controls Finder uses brought both back.

| Work | Details |
|---|---|
| File split | `Models/` (data) and `Views/` (UI) |
| List view | `NSTableView` — Name / Date Modified / Size / Kind columns, click-to-sort, remembered column widths |
| Icon view | `NSCollectionView` — rubber-band selection |
| Dragging | Multiple files at once; like Finder, drag on the name to move files, drag on empty space to select |
| Keyboard | Arrows, `⇧`+arrows, `⌘A`, `⌘↓`/`⌘↑`, type-to-select |
| Quick Look | `QLPreviewPanel` wired up directly → browse with arrow keys while the panel is open |
| Active pane | Border on the pane that receives keyboard input, `Tab`/`⇧Tab` to switch |

- **Approach:** shipped the list view first for a mid-version test, then finished the rest — splitting the biggest task to reduce risk.
- **Feedback:** "No delete is inconvenient" → made it the top priority of v4.

### v4. File operations

| Feature | Shortcut / how |
|---|---|
| Move to Trash | `⌘⌫` (never permanent; *Put Back* works) |
| Rename | `Return` → inline editing, base name selected |
| New folder | `⇧⌘N` → starts in rename mode |
| Copy / paste | `⌘C` / `⌘V` (works with Finder too) |
| Move | `⌥⌘V`, or press `⌘` after starting a drag |
| Copy path | `⌥⌘C` |
| Context menu | Open, Quick Look, Rename, Copy, Trash, Copy Path, Show in Finder |
| Shared refresh | Other panes showing the same folder update too |

- **Feedback applied:** the status bar's "XX GB available" (identical in every pane, so useless) became the **size of the current folder**, summed over subfolders **in the background** with a "Calculating…" state.
- `Return` changed from *open* to *rename* (same as Finder). Open is double-click, `⌘↓` or `⌘O`.
- **Verification:** new folder, rename, copy, move and "copy into itself" guards were tested automatically in a temporary folder instead of real files.

### v5. Sidebar and navigation

- **Drop rules finalized**

  | Drag | Drop on | Result |
  |---|---|---|
  | Sidebar item | Pane | The pane opens that folder |
  | Files / folders in a pane | Another pane | Copy (press `⌘` after starting the drag → move) |
  | Folder + **`⌥`** | Another pane | The pane opens that folder |
  | Folder in a pane | Sidebar | Added to favorites |
  | Files from Finder | Pane | Copy |

- Collapsible sidebar (`⌃⌘S`) with 5 default favorites (Desktop, Documents, Downloads, Home, Applications)
- Add favorites by drag & drop or right-click, reorder by dragging, remove via right-click — all saved
- `⇧⌘G` Go to Folder: absolute paths, `~` paths, relative paths, and file paths (selects the file)

### v6. Finishing touches

| Feature | Details |
|---|---|
| Background copying | The app stays responsive while copying large files; jobs queue up |
| Progress | Bottom-right panel: `1.2 GB / 4 GB · 30% · 1 waiting`, ⓧ to cancel |
| On cancel | Partially copied items go **to the Trash** |
| Move across disks | After copying, the original goes **to the Trash** |
| Quit confirmation | `⌘Q` during a copy → "Keep going / Cancel and quit" |
| Auto-refresh | Changes made by other apps appear within 0.4 s |
| Hidden files | `⇧⌘.` per pane, shown dimmed, setting saved |

- Background copying was the biggest task, so we first wrote a tiny test program to confirm how macOS's `copyfile` reports progress and handles cancellation.

### Wrap-up. Windows · icon · installer

- **Multiple windows:** `⌘N` works, but every window shared the same saved pane state → new windows start at the default folders; only the first window saves its state.
- **App icon:** 2×2 folders on blue, with the top-left yellow folder standing for the active pane — drawn in Swift code, no design tools (`Tools/make-icon.swift`).
- **Installer:** `./Tools/install.sh` builds a Release version and installs it into Applications; the previous version goes to the Trash.

### v7. Previews · expandable folders · icon size

Three requests after a few days of real use.

| Feature | Details |
|---|---|
| File previews | Images, PDFs, videos and documents show content thumbnails (`QuickLookThumbnailing`) — default icon first, swapped in when ready, cached |
| Expandable folders | List view moved to `NSOutlineView`: a `›` left of each folder icon expands it in place; `→`/`←`; expansion survives refreshes |
| Icon size slider | `⌘`-click the icon-view button → popover with a continuous slider: Small 50% · Normal · Big 150% · Huge 200%; applied instantly, **per pane**, resets to Normal on relaunch |

- **Decisions:** icon size is per pane; the `›` sits left of the icon, like Finder.
- **Fix:** Quick Look closed when moving with arrow keys in icon view (see #9 below).

### 1.1.0. Convenience features + Settings window

The first version after the public release (Release v1.0). From here on, version numbers follow `major.minor.patch`, so the version after v7 is **1.1.0** (new features bump the middle number). It was built in two stages with a test in between.

| Stage | Feature | Details |
|---|---|---|
| 1 | Open With | Context submenu: the default app "(default)" on top, other apps, then "Other…". With several files, only apps that can open all of them |
| 1 | Services | The list and icon views tell macOS they can hand over the selected files (`validRequestor`, `writeSelection`), so other apps' services appear in the context menu like in Finder |
| 1 | Path input | The *Go to Folder* toolbar button and sheet are gone; double-click the path at the top of a pane (or `⇧⌘G`, Go menu) to edit it in place |
| 1 | Favorites cleanup | Stored as bookmarks instead of path strings, so renamed folders are followed. Folders in the Trash or gone from a connected disk are removed; folders on a disconnected drive (`/Volumes/…`) stay, dimmed. The old list is migrated on first launch |
| 1 | Grid spacing | 50–150% slider under the icon size slider; scales the visible spacing (name margin, gap between items, gap between rows) |
| 1 | Icon size | Extended to 50–300% with six evenly spaced ticks. Above 200% previews are regenerated at a larger size; the preview cache is capped at about 200 MB |
| 2 | Settings window | `⌘,` or the gear button. Tabs: General (start folder per pane) / View / File operations (confirm Trash, folder size, default drag action) / Sidebar / Shortcuts / Advanced (reset). Defaults match 1.0 behavior |
| 2 | Custom shortcuts | Ten actions can be rebound. Plain letter keys, keys used by macOS and keys already in use are rejected. Fixed shortcuts and mouse gestures are listed in the same tab |

- **Changes after testing:** the slider popover covered too much of the window, so it shrank to 60% width and about half the height → text 10% larger → evenly spaced ticks instead of labels for icon size → path editing on double-click instead of a single click.
- **Moved to the next version:** "Layout at launch (columns × rows, up to 6 panes)" goes into 1.2.0 (free splitting), which rebuilds the pane structure.

---

## 4. Problems and solutions

| # | Problem | Cause | Fix |
|---|---|---|---|
| 1 | Build errors around `ObservableObject` | Recent Xcode checks module imports strictly | Add `import Combine` in every file that needs it |
| 2 | Dragging in a SwiftUI list selected a range instead | `List(selection:)` + `.onDrag` conflict on macOS | Switched to AppKit `NSTableView` / `NSCollectionView` |
| 3 | `open` error in the folder-watching code | Name clash with the `PaneModel.open(_:)` method | Call `Darwin.open` / `Darwin.close` explicitly |
| 4 | Cancelled copies reported success | `copyfile` returns 0 even when the callback aborts | Track cancellation separately; move partial items to the Trash |
| 5 | `self captured before all members were initialized` | A closure used a property before `init` finished | Compute into a local variable first |
| 6 | Icon added, but the Dock showed a blank icon | The Dock cached the icon-less first launch | Re-register with `lsregister -f` and relaunch (or `killall Dock`) |
| 7 | A dent where each folder's tab meets its body | Rounded corners of the tab and body overlapped | Draw the tab overlapping deeper into the body |
| 8 | Saved state mixed up across windows | State was keyed only by pane number (0–3) | Only the first window saves (`WindowPanes`); others start fresh |
| 9 | Quick Look closed on arrow keys in icon view | The collection view reports "deselect → select" in two steps, so the selection looks empty for a moment | Defer the Quick Look refresh by one run-loop turn and use the final selection |
| 10 | Shortcuts recorded with a Korean input source showed as "⌥⌘ㅅ" | The typed character depends on the input source | Derive the English letter from the key position (as Finder menus do) |
| 11 | Services appear directly in the context menu instead of under "Services ▸" | macOS inlines services when there are only a few | Expected behavior; unwanted items can be turned off in System Settings → Keyboard → Keyboard Shortcuts → Services |

---

## 5. Decisions made along the way

| When | Decision |
|---|---|
| Setup | Keep `⌘`-click on the top bar for merging |
| After v3 | Make Move to Trash (`⌘⌫`) the top priority of v4 |
| Before v4 | Status bar: disk free space → current folder size |
| Before v5 | Folder + `⌥` drop = the pane opens that folder |
| Wrap-up | New windows start at default folders / keep the name `QaudFInder` / icon first, then installer |
| v7 | Icon size per pane, `›` left of the icon |
| Release | MIT license, English & Korean docs, public repository |
| 1.1.0 planning | Free splitting (split any pane, remove the unmerge button), bring back Get Info and archive/extract, `major.minor.patch` version numbers |
| 1.1.0 | Path editing on double-click, Shortcuts tab in Settings, at most 6 panes (9 is too small on a laptop screen) |

**Intentionally left out:** permanent delete, batch rename, tags, tabs, recursive search (`⌘F`), NAS connections.
(Archive/extract and Get Info (`⌘I`) were brought back during 1.1.0 planning → planned for 1.3.0 and 1.4.0.)

---

## 6. Possible next steps

- Remember merged panes across launches (currently reset on relaunch) → to be solved by "remember layout" in 1.2.0
- Undo (`⌘Z`) — for now, *Put Back* from the Trash
- Auto-refresh for expanded subfolders changed by other apps (use ⟳ for now)

---

## 7. Looking back

- **Small steps, checked every time:** every version followed "build → compile → hands-on test → commit", so problems were always easy to trace.
- **Safety nets before risky features:** every destructive action goes through the Trash, so mistakes can be undone.
- **Try unfamiliar tech in isolation first:** features like copy progress were proven in a tiny test program before touching the app.
- **Real use sets the priorities:** "no delete", "useless disk-space label", "I need previews" — each became the top item of the next version.
