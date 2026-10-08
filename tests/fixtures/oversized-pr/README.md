# Fixture: oversized-pr

**Expected to be caught by:** `pr-size-guard` action (hard fail at 600 LOC).

Built by `tests/build-fixtures.sh` — appends 700 lines to `big.txt` between two commits to simulate a too-large PR diff.
