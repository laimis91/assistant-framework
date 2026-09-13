# Change-impact review projection

Load for a review that covers a behavior change, carries a change-impact
artifact, or has a locality/shared/unresolved decision. Record compact
applicability evidence for every behavior change. Keep this outside the fresh
reviewer context bundle: the existing 5653-word reviewer-context budget remains
unchanged.

Resolve the common checker from the loaded skill directory as
`../../tools/change-impact/validate-change-impact.cjs`, quoted and invoked with
explicit files under Node 22+ only for shared, materially unresolved, or
explicitly carried expanded work. This works for selective installs and custom
homes; do not use the process cwd or require assistant-workflow. Evidenced local
work keeps ordinary review and verification without a Node gate.

Use the existing canonical `scope_manifest`, `coverage_ledger`, current review
snapshot, and concern IDs to create the v1 completion projection. Map each
captured requirement once; do not create an impact-specific coverage ledger.
Read-only audit can identify absent/stale mappings and report the gap. Review
fix must refresh its frozen snapshot after mutation. A valid impact projection
never replaces `final_summary.coverage_complete`, required terminal passes, or
the CLEAN/ISSUES_FIXED decision.
