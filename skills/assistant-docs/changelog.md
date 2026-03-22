# Changelog Generator

## Protocol

### Step 1: Determine Scope

- **Between versions**: `git log v1.0.0..v1.1.0`
- **Since last release**: `git log $(git describe --tags --abbrev=0)..HEAD`
- **Custom range**: as specified by user

### Step 2: Categorize Changes

Read each commit and categorize:

| Category | Includes |
|---|---|
| **Added** | New features, new endpoints, new capabilities |
| **Changed** | Modifications to existing behavior |
| **Fixed** | Bug fixes |
| **Removed** | Removed features or deprecated items |
| **Security** | Security-related changes |
| **Breaking** | Changes that break backward compatibility |

Skip: merge commits, formatting-only changes, internal refactors with no user-visible impact.

### Step 3: Generate

Follow [Keep a Changelog](https://keepachangelog.com/) format:

```markdown
## [Version] - YYYY-MM-DD

### Breaking Changes
- **[component]**: [what changed and migration path]

### Added
- [feature description] ([#PR] if available)

### Changed
- [change description]

### Fixed
- [bug description and what was wrong]

### Security
- [security fix description]
```

### Step 4: Quality Check

- Every entry is user-facing (no internal implementation details)
- Breaking changes have migration instructions
- Entries are concise (one line each, detail in PRs)
- Chronological order within categories

### Output

- Prepend to existing `CHANGELOG.md` if it exists
- Create `CHANGELOG.md` if it doesn't
- Never overwrite existing changelog entries
