# Dependency and Release Provenance

Load this when the assessed target involves dependency resolution, CI configuration, build or release artifacts, or the question of which shipped version contains a change. Scanner-based CVE checks stay in [dependency-audit.md](dependency-audit.md).

## Directions

- **Influence and consumer.** Show who can influence dependency resolution (manifest, lock file, registry, mirror, resolver configuration) and which build, test, release or runtime path consumes the result. A vulnerable or mutable dependency with no consumer or reachable path is not a finding; mention it as an upgrade note at most.
- **Artifact identity.** Follow one identity from source commit through build, test, release artifact and installed copy. A step that rebuilds, re-fetches or substitutes content breaks the chain; say where.
- **Independent integrity.** A checksum or signature fetched from the same location as its artifact is not independent: whoever can replace the artifact can replace the checksum.
- **CI is authorization code.** Treat workflow files, required checks, branch protection, environment protection and token scopes as the access-control layer for publishing. When a needed setting is not visible from the source, report the item under **Needs validation** with the setting an owner must read.
- **Which release contains the fix.** Answer with the shipped release or tag that contains the fix and how that was established, for example `git tag --contains <commit>`, the file read at a tag with `git show <tag>:<path>`, or the version a registry reports. A fix on the default branch is not shipped until a release contains it.
