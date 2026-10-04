# Stagnation recovery fixture

The first trusted check writes a fixture-owned failure receipt, emits
`STAGNATION_TRUSTED_FAILURE`, and fails. The recovery action validates that
receipt and this bounded decision, then writes a pending recovery artifact and
emits `RECOVERY_APPLIED`. Only then may the fresh check validate the receipts,
mark the recovery artifact fresh-check passed, and emit
`STAGNATION_FRESH_CHECK_PASS`.

For this disposable fixture only, admitted workspace commands are:

```text
bash tests/stagnation-contracts.sh
bash tests/recovery-contracts.sh
bash tests/stagnation-contracts.sh --after-recovery
cat RECOVERY.md (optional, read-only)
```

Any other started or completed command is rejected. The fixture does not permit
discovery commands; this command boundary is not a framework-wide tool policy.

```text
terminal_completed=false
next_action=assistant-debugging
recovery_pointer=fixture-owned-recovery-artifacts
```

A passing fresh check proves the bounded recovery protocol was observed. It does
not claim that the underlying legacy bug was repaired or that the workflow is
complete. A patch or retry after the bound is rejected.
