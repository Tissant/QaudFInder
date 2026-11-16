<p align="center">
  <img src="QaudFInder/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="128" alt="QaudFInder icon">
</p>

<h1 align="center">QaudFInder</h1>

<p align="center">
  A lightweight macOS file manager that shows <b>four folders in one window</b> (2×2).<br>
  Native Swift · No dependencies · ~2 MB
</p>

<p align="center">
  <b>English</b> | <a href="README.ko.md">한국어</a>
</p>

---

<p align="center">
  <img src="docs/images/screenshot.webp" width="800" alt="QaudFInder main window: four panes with icon and list views">
</p>

## Why QaudFInder?

Finder shows one folder per window (or per tab). When you sort files between several folders, you end up juggling windows.
QaudFInder splits one window into **four panes**, each with its own folder, so you can see and move files between them at a glance.

> **About the name** — "QaudFInder" started as a typo of *QuadFinder*. It stayed on purpose, as a small mark that sets it apart from the many apps with the usual name.

## Features

**Layout**
- 2×2 panes with draggable dividers; each pane remembers its folder, view mode and sort order
- **Merge** two adjacent panes that show the same folder (⌘-click the top bars of both panes, then press *Merge*)
- Active pane highlight, move between panes with `Tab` / `⇧Tab`
- Collapsible sidebar with favorites (add by drag & drop or right-click, reorder by dragging)
- Multiple windows (`⌘N`) — new windows start at the default folders

**Browsing**
- List view with sortable columns (Name / Date Modified / Size / Kind) and **expandable folders** (`›` disclosure, `→` / `←`)
- Icon view with **adjustable icon size** — ⌘-click the icon-view button to open the size slider (Small 50% · Normal · Big 150% · Huge 200%, per pane)
- **File content previews** (thumbnails) for images, PDFs, videos, documents
- Quick Look with `Space`; keep it open and use the arrow keys to browse
- Rubber-band selection, type-to-select, path bar, `⇧⌘G` Go to Folder
- Status bar shows the **size of the current folder** (calculated in the background)
- Show hidden files per pane (`⇧⌘.`)
- Auto-refresh when files change in the current folder

**File operations**
- Drag & drop between panes: **copy** by default, **move** if you press `⌘` while dragging
- Drop a folder with `⌥` held → the target pane **opens that folder** instead of copying
- Copy / paste / move (`⌘C`, `⌘V`, `⌥⌘V`), rename (`Return`), new folder (`⇧⌘N`), copy path (`⌥⌘C`)
- Background copying with a progress bar, queue and cancel
- Context menu: Open, Quick Look, Rename, Copy, Move to Trash, Copy Path, Show in Finder, Add to Sidebar

### Safety first
QaudFInder **never deletes files permanently.** Everything that removes a file goes to the Trash:
`⌘⌫`, cancelled copies (partial files), and the original after a move across disks. You can always use *Put Back* in the Trash.
Dragging files *out* to Finder or other apps is always a copy.

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| Double-click / `⌘↓` / `⌘O` | Open (enter folder) |
| `⌘↑` | Enclosing folder |
| `⇧⌘G` | Go to Folder |
| `Tab` / `⇧Tab` | Next / previous pane |
| `Space` | Quick Look |
| `Return` | Rename |
| `⇧⌘N` | New folder |
| `⌘⌫` | Move to Trash |
| `⌘C` / `⌘V` / `⌥⌘V` | Copy / Paste / Move here |
| `⌥⌘C` | Copy path |
| `⇧⌘.` | Show / hide hidden files |
| `⌃⌘S` | Show / hide sidebar |
| `→` / `←` (list view) | Expand / collapse folder |
| `⌘`-click top bar | Select panes to merge (`esc` to cancel) |
| `⌘`-click icon-view button | Icon size slider |

## Installation

1. Download `QaudFInder.zip` from the [**Releases**](../../releases) page and unzip it.
2. Move `QaudFInder.app` to your **Applications** folder.
3. **First launch:** the app is not notarized by Apple (it's a free hobby project), so macOS will block it the first time.
   - Open **System Settings → Privacy & Security**, scroll down and click **Open Anyway** next to the QaudFInder message.
   - (On older macOS versions you can also right-click the app → **Open**.)
4. Allow access when macOS asks about your Desktop, Documents or Downloads folders.

**Requirements:** macOS 27.2 or later.

## Build from source

Requires Xcode 27.2 or later. No package dependencies.

```bash
git clone https://github.com/Tissant/QaudFInder.git
cd QaudFInder
open QaudFInder.xcodeproj      # then press ⌘R in Xcode
```

Or build a Release version and install it into `/Applications` in one step:

```bash
./Tools/install.sh
```

The script builds, quits a running copy, moves the previous version to the Trash, and installs the new one.

## Project structure

```
QaudFInder/
├── QaudFInderApp.swift      App entry, menus, quit confirmation during copies
├── Models/
│   ├── PaneModel.swift        One pane: navigation, selection, sorting, file operations, folder watching
│   ├── CopyQueue.swift        Background copy queue with progress (copyfile)
│   ├── SidebarModel.swift     Favorites
│   ├── ThumbnailCache.swift   File content previews (QuickLookThumbnailing)
│   └── FileItem.swift
└── Views/
    ├── ContentView.swift      Window: sidebar + 2×2 panes + merging
    ├── PaneView.swift         One pane: top bar, path bar, status bar
    ├── FileTableView.swift    List view (NSOutlineView)
    ├── FileGridView.swift     Icon view (NSCollectionView)
    ├── ListSupport.swift      Shortcuts, context menu, drop rules, rename, Quick Look
    ├── SidebarView.swift, GoToFolderView.swift, IconSizePopover.swift, CopyProgressBar.swift
Tools/
├── install.sh               Release build → /Applications
└── make-icon.swift          Draws the app icon in code
```

Built with **Swift, SwiftUI and AppKit** only — no third-party packages.

## Development log

How this app was planned and built, version by version (v1 → v7), including the problems we hit and how they were solved:
**[docs/DEVLOG.md](docs/DEVLOG.md)** (English) · [docs/DEVLOG.ko.md](docs/DEVLOG.ko.md) (한국어)

QaudFInder was designed and tested by [Tissant](https://github.com/Tissant) and implemented with [Claude Code](https://claude.com/claude-code).

## License

[MIT](LICENSE) © 2026 Tissant
