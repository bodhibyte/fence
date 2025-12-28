# Safety Check Testing Commands

## Trigger Safety Check on Next Launch

Clear the stored versions so the app thinks there's been a version change:

```bash
defaults delete org.eyebeam.SelfControl SCSafetyCheck_LastTestedAppVersion
defaults delete org.eyebeam.SelfControl SCSafetyCheck_LastTestedOSVersion
```

Then run the app - it will prompt "Safety Check Recommended" within 1 second.

## Check Current Stored Versions

```bash
defaults read org.eyebeam.SelfControl SCSafetyCheck_LastTestedAppVersion
defaults read org.eyebeam.SelfControl SCSafetyCheck_LastTestedOSVersion
```

## Reset Everything (Nuclear Option)

```bash
# Clear ALL SelfControl user defaults
defaults delete org.eyebeam.SelfControl
```
