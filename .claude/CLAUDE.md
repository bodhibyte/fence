# SelfControl - Agent Instructions

> **CRITICAL:** This file MUST be read by any AI agent before making changes to this codebase.

---

## Project Overview

**SelfControl** is a macOS app that blocks websites/network resources for a set time. The block cannot be disabled until the timer expires—even rebooting won't help. Written in Objective-C with a privileged daemon architecture.

**Current Focus:** Adding app blocking capability (block Terminal, Cursor, etc. in addition to websites)

---

## Documentation Map

```
📁 selfcontrol/
├── 📄 SYSTEM_ARCHITECTURE.md      ← START HERE: Complete architecture
│   ├── Component deep dives
│   ├── Mermaid flow diagrams
│   ├── Security model
│   └── Extension points
│
├── 📁 docs/
│   ├── 📄 INDEX.md                ← Quick navigation & module map
│   ├── 📄 BLOCKING_MECHANISM.md   ← How blocking works + app blocking design
│   ├── 📄 dictionary.md           ← Domain terminology index
│   └── 📁 dictionary/             ← Full term definitions
│
└── 📁 .claude/
    └── 📄 CLAUDE.md               ← You are here
```

---

## Shared Vocabulary Protocol

### Dictionary Location
- **Index:** `docs/dictionary.md` — Load this at session start
- **Full entries:** `docs/dictionary/[term].md` — Search on-demand

### Key Terms (Quick Reference)

| Term | Definition |
|------|------------|
| **Editor** | UI sheet for defining allowed windows per bundle/day |
| **Allowed Window** | User-defined time range when bundle is NOT blocked |
| **Block Window** | Computed inverse - when blocking IS active |
| **Segment** | Time slice with consistent set of active bundles |
| **Merged Blocklist** | Combined entries from all active bundles in a segment |
| **Committed State** | Schedule locked after user confirms |
| **Pre-Authorized Schedule** | Segment registered with daemon (password-free execution) |
| **Bundle** | Named group of websites/apps |
| **Entry** | Single blocked item (domain or app bundle ID) |

### How to Reference

1. Load `docs/dictionary.md` (the index) at session start
2. When you encounter a term from the index, read its full entry in `docs/dictionary/`
3. Use the dictionary definition—NOT your general knowledge
4. If a term is missing, flag it and ask for clarification

**Example workflow:**
```
User: "When the user is in a committed state, disable the editor"

Agent thinks:
- "committed state" → read docs/dictionary/committed-state.md
- "editor" → read docs/dictionary/editor.md
- Now I understand: disable SCDayScheduleEditorController when isCommitted=YES
```

### When Modifying Code

If your changes affect files listed in any dictionary term's "Code Locations":
1. Re-read that term's full entry
2. Verify your changes align with the defined behavior
3. Update the dictionary entry if behavior has changed

### When You Encounter an Undefined Term

If a term seems domain-specific but isn't in the dictionary:
1. Flag it in your response: "⚠️ Term '[X]' not found in dictionary"
2. Ask the user for a definition
3. Suggest adding it to the dictionary using `/define-terms`

---

## Agent Responsibilities

### Before Making Changes

1. **Read the relevant documentation:**
   - For architecture questions → `SYSTEM_ARCHITECTURE.md`
   - For blocking logic → `docs/BLOCKING_MECHANISM.md`
   - For quick file lookup → `docs/INDEX.md`

2. **Understand the component you're modifying:**
   - App layer: `AppController.m`, `TimerWindowController.m`
   - Daemon layer: `Daemon/SCDaemon*.m`
   - Blocking layer: `Block Management/*.m`
   - Common utilities: `Common/*.m`

### After Making Changes

**⚠️ MANDATORY:** Update documentation when you:

| Change Type | Update These Files |
|-------------|--------------------|
| New feature/component | `SYSTEM_ARCHITECTURE.md` (add section) |
| Modified blocking logic | `docs/BLOCKING_MECHANISM.md` |
| New files created | `docs/INDEX.md` (module map) |
| API/XPC changes | `SYSTEM_ARCHITECTURE.md` Section 9 |
| New settings | `SYSTEM_ARCHITECTURE.md` Section 9.2 |

### Documentation Standards

- Keep Mermaid diagrams in sync with code
- Update "Key Files" tables when adding files
- Add new error codes to error code table
- Update file line counts if significantly changed

---

## Key Architecture Points

```
┌─────────────────────────────────────────────────────────────┐
│  SelfControl.app (User)  ←── XPC ──→  selfcontrold (Root)  │
│         │                                    │              │
│         └── UI/Settings                      └── Blocking   │
│                                                  ├── /etc/hosts
│                                                  └── pfctl
└─────────────────────────────────────────────────────────────┘
```

**Critical Concepts:**
1. **Dual-layer blocking** - DNS redirect + packet filter
2. **Privilege separation** - App cannot modify system files
3. **Continuous verification** - 1-second checkup timer
4. **Tamper resistance** - Settings in `/usr/local/etc/`

---

## Current Task: App Blocking - IMPLEMENTED

**Status:** Implemented and ready for testing

**What was added:**

1. **App Blocking Engine** (`Block Management/AppBlocker.h/m`)
   - Polls running apps every 500ms
   - Kills apps matching blocked bundle IDs
   - Thread-safe with NSLock

2. **Entry Format Extension** (`Block Management/SCBlockEntry.h/m`)
   - Added `appBundleID` property
   - Parses `app:com.bundle.id` format
   - `isAppEntry` method to check entry type

3. **BlockManager Integration** (`Block Management/BlockManager.h/m`)
   - Routes app entries to AppBlocker
   - Starts/stops monitoring in finalizeBlock/clearBlock

4. **Debug Mode Safety** (`Common/SCDebugUtilities.h/m`)
   - "Debug > Disable All Blocking" menu (DEBUG builds only)
   - `#ifdef DEBUG` wrapping - compiled out of release builds
   - Visual indicator in window title

5. **UI for Adding Apps** (`DomainListWindowController.m`)
   - `addAppToBlocklist:` action opens app picker
   - App entries shown in purple with app name

6. **Startup Safety Check** (`Common/SCStartupSafetyCheck.h/m`, `SCSafetyCheckWindowController.h/m`)
   - Triggers on macOS or app version change (DEBUG builds only)
   - Runs 30-second test blocking example.com + Calculator
   - Verifies hosts, PF, and app blocking work
   - Verifies cleanup after block expires
   - Uses `SCVersionTracker` to detect version changes

**Entry Format:**
```
app:com.apple.Terminal     - Block Terminal
app:com.cursor.Cursor      - Block Cursor
facebook.com               - Existing website block
```

**Debug Mode:**
- Only in DEBUG builds
- Menu: Debug > Disable All Blocking
- Disables ALL blocking (apps + websites)

---

## Quick Reference

### Important Paths
| Path | Purpose |
|------|---------|
| `/etc/hosts` | DNS redirects |
| `/etc/pf.anchors/org.eyebeam` | Firewall rules |
| `/usr/local/etc/.{hash}.plist` | Settings (root only) |

### Key Classes
| Class | Purpose |
|-------|---------|
| `BlockManager` | Orchestrates all blocking |
| `HostFileBlocker` | Modifies /etc/hosts |
| `PacketFilter` | Creates PF rules |
| `SCDaemonBlockMethods` | Daemon block operations |
| `SCBlockEntry` | Block entry data model |

### Build & Run
```bash
# Build
xcodebuild -project SelfControl.xcodeproj -scheme SelfControl

# Run (requires signing for SMJobBless)
open build/Release/SelfControl.app
```

---

## Code Style

- **Language:** Objective-C
- **Naming:** `camelCase` for methods/variables, `PascalCase` for classes
- **Comments:** Only where logic isn't self-evident
- **Threading:** Use `NSLock` for shared state, `dispatch_async` for background work

---

## Testing Checklist

Before submitting changes:
- [ ] Block starts correctly
- [ ] Block persists through reboot
- [ ] Timer displays correctly
- [ ] Block ends at correct time
- [ ] No memory leaks (Instruments)
- [ ] Daemon terminates when idle

---

*Last updated: December 2024*
*Update this file when making significant architectural changes*
