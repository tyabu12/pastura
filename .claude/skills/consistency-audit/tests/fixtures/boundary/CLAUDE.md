# Boundary fixture

Regression for the offset-based fixer. The stale value `7.10.0` appears twice
on the line below: once embedded in the non-word-bounded token `v7.10.0x`
(which the detector must NOT count or rewrite) and once as a real, bounded
version token. `--fix` must rewrite only the bounded token, leaving `v7.10.0x`
byte-for-byte intact — a boundary-unaware `str.replace` would corrupt the
first occurrence instead.

Track GRDB v7.10.0x build; pinned GRDB version 7.10.0 here.
