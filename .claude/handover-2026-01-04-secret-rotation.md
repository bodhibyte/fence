# Handover: Secret Rotation & Git History Cleanup

**Created:** 2026-01-04
**Status:** Pending
**Priority:** CRITICAL - Public repo with exposed secrets

---

## Summary

A git history audit found exposed secrets in the public `fence` repository (https://github.com/VishalJ99/fence). One secret has been rotated, one still needs rotation.

---

## Secrets Status

| Secret | Exposed Value | Current Status | Action Needed |
|--------|---------------|----------------|---------------|
| Resend API Key | `re_Hje6jJp1_K2dvGkbNcosHXJLLZ3uf7G4Y` | ✅ ROTATED (now `re_3oBS74ED_...`) | Revoke old key in Resend dashboard |
| LICENSE_SECRET_KEY | `1fd414f5643f33b0b713989d50093ae34ef799399adf5b7ac90655ac4ea72f73` | ⚠️ STILL EXPOSED | Must rotate |

---

## Exposure Details

### LICENSE_SECRET_KEY
- **File:** `Build SelfControl_2025-12-31T01-07-30.txt` (build log)
- **Commit:** `6d46cbc09dbeebecfa4ac90afdea5f02c5b7a14a`
- **How:** Xcode build log captured clang command with `-D LICENSE_SECRET_KEY=...`
- **Status:** File is STILL in repo (not just history)

### Resend API Key (already rotated)
- **File:** `docs/LICENSING_SPEC.md`
- **Commit:** `31cfc2af9ef8758df4e73a7e0e1a97799b7de7d3`
- **Status:** Removed from HEAD but still in git history

---

## Remediation Steps

### Step 1: Remove Build Log from Repo

```bash
cd ~/selfcontrol
git rm "Build SelfControl_2025-12-31T01-07-30.txt"
echo "Build *.txt" >> .gitignore
echo "*.profraw" >> .gitignore
git add .gitignore
git commit -m "Remove build log with exposed secrets, update gitignore"
git push
```

### Step 2: Generate New LICENSE_SECRET_KEY

```bash
openssl rand -hex 32
```

Save this new key - you'll need it in 3 places.

### Step 3: Update LICENSE_SECRET_KEY Everywhere

#### 3a. Xcode Project (Secrets.xcconfig)
```bash
# Edit ~/selfcontrol/Secrets.xcconfig
LICENSE_SECRET_KEY = <new-64-char-hex-key>
```

#### 3b. Cloudflare Pages
1. Go to: https://dash.cloudflare.com
2. Navigate: Pages → fence-web → Settings → Environment variables
3. Update `LICENSE_SECRET_KEY` with new value
4. Save (applies to next deployment)

#### 3c. Railway
1. Go to: https://railway.app/dashboard
2. Navigate: fence project → Variables
3. Update `LICENSE_SECRET_KEY` with new value
4. Redeploy service

### Step 4: Revoke Old Resend API Key

1. Go to: https://resend.com/api-keys
2. Find key starting with `re_Hje6jJp1_`
3. Click delete/revoke

### Step 5: Rewrite Git History (Optional but Recommended)

Since the repo is public, secrets remain in git history even after removal. Use BFG Repo-Cleaner:

```bash
# Install BFG
brew install bfg

# Create secrets file to redact
cat > /tmp/fence-secrets.txt << 'EOF'
re_Hje6jJp1_K2dvGkbNcosHXJLLZ3uf7G4Y
1fd414f5643f33b0b713989d50093ae34ef799399adf5b7ac90655ac4ea72f73
EOF

# Clone a fresh mirror
cd /tmp
git clone --mirror https://github.com/VishalJ99/fence.git fence-mirror

# Run BFG to redact secrets
bfg --replace-text /tmp/fence-secrets.txt fence-mirror
bfg --delete-files "Build SelfControl_*.txt" fence-mirror

# Clean up
cd fence-mirror
git reflog expire --expire=now --all
git gc --prune=now --aggressive

# Force push (WARNING: rewrites history for all collaborators)
git push --force

# Update local repo
cd ~/selfcontrol
git fetch --all
git reset --hard origin/master
```

### Step 6: Rebuild and Release Fence.app

After updating `Secrets.xcconfig`:

```bash
cd ~/selfcontrol
./scripts/build-release.sh <new-version>
```

Upload new DMG to distribution channel.

---

## Impact of LICENSE_SECRET_KEY Rotation

**Existing licenses will break** after rotation because:
- Licenses are signed with HMAC-SHA256 using the secret
- New secret = old signatures won't verify

**Options:**
1. **Reissue all licenses** - Email customers new codes
2. **Dual-key validation** - Temporarily accept both old and new keys in app
3. **Grandfather existing** - Keep old key in app for verification only, use new key for generation

---

## Verification Checklist

After completing all steps:

- [ ] Build log file removed from repo
- [ ] .gitignore updated to prevent future build logs
- [ ] New LICENSE_SECRET_KEY generated
- [ ] Secrets.xcconfig updated
- [ ] Cloudflare env var updated
- [ ] Railway env var updated
- [ ] Old Resend key revoked
- [ ] Git history rewritten (optional)
- [ ] New app version built and released
- [ ] Existing customer licenses handled

---

## Files Referenced

- `~/selfcontrol/Build SelfControl_2025-12-31T01-07-30.txt` - DELETE THIS
- `~/selfcontrol/Secrets.xcconfig` - Update LICENSE_SECRET_KEY
- `~/selfcontrol/.gitignore` - Add build log patterns
- `~/selfcontrol/docs/LICENSING_SPEC.md` - Had Resend key (in history)

---

## Contact

If resuming this task, the git history audit was performed by searching:
- `git log -p --all | grep -E "(sk_live_|sk_test_|re_[A-Za-z0-9]|LICENSE_SECRET|postgres://)"`
