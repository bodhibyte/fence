# SelfControl Project Overview

## Purpose
SelfControl is a macOS application that blocks access to specified websites/network resources for a defined time period. The block cannot be disabled until the timer expires—even rebooting won't help.

## Tech Stack
- **Language:** Objective-C
- **Frameworks:** Cocoa, Security.framework, ServiceManagement
- **IPC:** XPC (Mach message-based)
- **Firewall:** macOS Packet Filter (PF/pf.conf)
- **DNS Override:** /etc/hosts modification
- **Build System:** Xcode/xcodebuild

## Architecture
- **User Space:** SelfControl.app, selfcontrol-cli
- **Privileged Space (root):** selfcontrold daemon
- **Triple-layer blocking:** /etc/hosts + PF firewall + App killer

## Key Directories
- `Block Management/` - Core blocking logic
- `Daemon/` - Privileged daemon code
- `Common/` - Shared utilities
- `.claude/CLAUDE.md` - Agent instructions (READ FIRST)
- `SYSTEM_ARCHITECTURE.md` - Full architecture docs
- `docs/` - Additional documentation
