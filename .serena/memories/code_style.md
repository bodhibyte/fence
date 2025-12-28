# SelfControl Code Style

- **Language:** Objective-C
- **Naming:** `camelCase` for methods/variables, `PascalCase` for classes
- **Comments:** Only where logic isn't self-evident
- **Threading:** Use `NSLock` for shared state, `dispatch_async` for background work
- **Prefix:** `SC` prefix for all classes (e.g., `SCBlockEntry`, `SCScheduleManager`)
