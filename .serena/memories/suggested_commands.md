# SelfControl Development Commands

## Build
```bash
xcodebuild -project SelfControl.xcodeproj -scheme SelfControl
```

## Run
```bash
open build/Release/SelfControl.app
```

## System (macOS/Darwin)
Standard Unix commands work: `git`, `ls`, `cd`, `grep`, `find`

Note: Requires code signing for SMJobBless (daemon installation)
