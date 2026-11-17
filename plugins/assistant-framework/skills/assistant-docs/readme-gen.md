# README Generator

## Protocol

### Step 1: Analyze Project

Gather from code:
- Project name and description (from .csproj, package.json, or top-level code)
- Tech stack (languages, frameworks, major dependencies)
- Build/run commands (from scripts, Makefile, CI config)
- Test commands
- Entry points
- Configuration requirements
- License

### Step 2: Check Existing README

If README.md exists:
- Identify sections that are accurate vs. stale
- Preserve user-written sections (motivation, contributing, etc.)
- Update only generated sections
- Never overwrite the entire file

### Step 3: Generate

```markdown
# [Project Name]

[One-line description derived from code purpose]

## What it does

[2-3 sentences explaining the project's purpose, derived from code analysis]

## Quick Start

### Prerequisites
- [runtime] [version]
- [tools needed]

### Setup
```bash
[actual setup commands from the project]
```

### Run
```bash
[actual run command]
```

### Test
```bash
[actual test command]
```

## Project Structure

```
[abbreviated tree showing key directories with one-line descriptions]
```

## Configuration

| Variable | Purpose | Default |
|---|---|---|
| [var] | [purpose] | [default or required] |

## [Additional sections as warranted by the project]
```

### Rules

- **Don't pad** — a 100-line project gets a 20-line README, not a 200-line one
- **Use actual commands** — don't guess build commands, find them in the project
- **Test the commands** — if possible, verify they work before documenting
- **Match existing tone** — if the README is casual, keep it casual
- **Preserve human content** — badges, motivation sections, contributing guides are user-maintained
