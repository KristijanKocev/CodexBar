---
summary: "Current keychain behavior: legacy migration, Claude OAuth keychain bootstrap, and prompt mitigation."
read_when:
  - Investigating Keychain prompts
  - Auditing Claude OAuth keychain behavior
  - Comparing legacy keychain docs vs current architecture
---

# Keychain Fix: Current State

## Scope change from the original doc
The original fix (migrating legacy CodexBar keychain items to `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`) is
still in place, but the architecture has changed:

- Provider settings and manual secrets are now persisted in `~/.codexbar/config.json`.
- Legacy keychain stores are still present mainly to migrate old installs, then clear old items.
- Keychain is still used for runtime cache entries (for example `com.steipete.codexbar.cache`) and Claude OAuth
  bootstrap reads from Claude CLI keychain (`Claude Code-credentials`).

## Then vs now

| Previous statement in this doc | Current behavior |
| --- | --- |
| CodexBar stores provider credentials only in keychain | Manual/provider settings are config-file backed (`~/.codexbar/config.json`), while keychain is still used for runtime caches and Claude OAuth bootstrap fallback. |
| `ClaudeOAuthCredentials.swift` migrated CodexBar-owned Claude OAuth keychain items | Claude OAuth primary source is Claude CLI keychain service (`Claude Code-credentials`), with CodexBar cache in `com.steipete.codexbar.cache` (`oauth.claude`). |
| Migration runs in `CodexBarApp.init()` | Migration runs in `HiddenWindowView` `.task` via detached task (`KeychainMigration.migrateIfNeeded()`). |
| Post-migration prompts should be zero in all Claude paths | Legacy-store prompts are reduced; Claude OAuth bootstrap can still prompt when reading Claude CLI keychain, with cooldown + no-UI probes to prevent storms. |
| Log category is `KeychainMigration` | Category is `keychain-migration` (kebab-case). |

## Current keychain surfaces for Claude

### 1. Legacy CodexBar keychain migration (V1)
`Sources/CodexBar/KeychainMigration.swift` migrates legacy `com.steipete.CodexBar` items (for example
`claude-cookie`) to `AfterFirstUnlockThisDeviceOnly`.

- Gate key: `KeychainMigrationV1Completed`
- Runs once unless flag is reset.
- Covers legacy CodexBar-managed accounts only (not Claude CLI's own keychain service).

### 2. Claude OAuth bootstrap path
`Sources/CodexBarCore/Providers/Claude/ClaudeOAuth/ClaudeOAuthCredentials.swift`

Load order for credentials:
1. Environment override (`CODEXBAR_CLAUDE_OAUTH_TOKEN`, scopes env key).
2. In-memory cache.
3. CodexBar keychain cache (`com.steipete.codexbar.cache`, account `oauth.claude`).
4. `~/.claude/.credentials.json`.
5. Claude CLI keychain service: `Claude Code-credentials` (promptable fallback).

Prompt mitigation:
- Non-interactive keychain probes use `KeychainNoUIQuery` (`LAContext.interactionNotAllowed` + `kSecUseAuthenticationUIFail`).
- Pre-alert is shown only when preflight suggests interaction may be required.
- Denials are cooled down in the background via `claudeOAuthKeychainDeniedUntil`
  (`ClaudeOAuthKeychainAccessGate`). User actions (menu open / manual refresh) clear this cooldown.
- Auto-mode availability checks use non-interactive loads with prompt cooldown respected.
- Background cache-sync-on-change also performs non-interactive Claude keychain probes (`syncWithClaudeKeychainIfChanged`)
  and can update cached OAuth data when the token changes.

### Claude keychain prompt behavior (fixed)
When CodexBar does not have usable OAuth credentials in its own cache (`com.steipete.codexbar.cache` / `oauth.claude`),
bootstrap falls through to Claude CLI keychain reads.

The flow uses two query shapes:
1. **persistentRef-based read**: Reads data using the persistent reference of a discovered keychain candidate.
2. **service-based legacy read**: Reads data using only the service name (fallback for old keychain entries).

**Previous behavior**: If the persistentRef-based read returned empty/nil, the code would fall through to the legacy
service-based query. Because macOS authorizes each query shape separately, this could cause a second keychain prompt
even after the user clicked "Always Allow" on the first prompt.

**Current behavior**: When keychain candidates are discovered, only the persistentRef-based query is used. The legacy
fallback is now reserved for cases where **no candidates** are found (e.g., very old keychain entries created before
the multi-entry discovery code existed). This prevents the double-prompt scenario.

If you still see repeated prompts:
- Ensure you clicked **"Always Allow"** (not just "Allow") on the keychain prompt.
- Check that you're using the latest CodexBar version with this fix.
- The fix only applies to scenarios where candidates are found; if you have a very old keychain setup, one-time
  prompts may still occur during migration.

### 3. Claude web cookie cache
`Sources/CodexBarCore/CookieHeaderCache.swift` and `Sources/CodexBarCore/KeychainCacheStore.swift`

- Browser-imported Claude session cookies are cached in keychain service `com.steipete.codexbar.cache`.
- Account key is `cookie.claude`.
- Cache writes use `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.

## What still uses `ThisDeviceOnly`

- Legacy store implementations (`CookieHeaderStore`, token stores, MiniMax stores) still write using
  `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
- Keychain cache store (`com.steipete.codexbar.cache`) also writes with `ThisDeviceOnly`.

## Disable keychain access behavior

`Advanced -> Disable Keychain access` sets `debugDisableKeychainAccess` and flips `KeychainAccessGate.isDisabled`.

Effects:
- Blocks keychain reads/writes in legacy stores.
- Disables keychain-backed cookie auto-import paths.
- Forces cookie source resolution to manual/off where applicable.

## Verification

### Check legacy migration flag
```bash
defaults read com.steipete.codexbar KeychainMigrationV1Completed
```

### Check Claude OAuth keychain cooldown
```bash
defaults read com.steipete.codexbar claudeOAuthKeychainDeniedUntil
```

### Inspect keychain-related logs
```bash
log show --predicate 'subsystem == "com.steipete.codexbar" && (category == "keychain-migration" || category == "keychain-preflight" || category == "keychain-prompt" || category == "keychain-cache" || category == "claude-usage" || category == "cookie-cache")' --last 10m
```

### Reset migration for local testing
```bash
defaults delete com.steipete.codexbar KeychainMigrationV1Completed
./Scripts/compile_and_run.sh
```

## Key files (current)

- `Sources/CodexBar/KeychainMigration.swift`
- `Sources/CodexBar/HiddenWindowView.swift`
- `Sources/CodexBarCore/Providers/Claude/ClaudeOAuth/ClaudeOAuthCredentials.swift`
- `Sources/CodexBarCore/Providers/Claude/ClaudeOAuth/ClaudeOAuthKeychainAccessGate.swift`
- `Sources/CodexBarCore/KeychainAccessPreflight.swift`
- `Sources/CodexBarCore/KeychainNoUIQuery.swift`
- `Sources/CodexBarCore/KeychainCacheStore.swift`
- `Sources/CodexBarCore/CookieHeaderCache.swift`
