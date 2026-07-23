# `PasswordPolicy` — Weighted Password Strength Specification

## Overview

This document specifies an Elixir module named `PasswordPolicy`. Rather than treating every rule as an equal pass/fail gate, the module scores password *strength* on a 0–100 scale and accepts or rejects a candidate password based on a configurable threshold. The deliverable is the complete module in a single file.

The implementation must rely solely on the Elixir/OTP standard library; no external dependencies are permitted for any part of the logic. In particular, Levenshtein distance must be implemented within the module itself using dynamic programming, not taken from an external library.

## API

The module exposes exactly one public function:

- `PasswordPolicy.evaluate(password, context)` — returns `{:accepted, score}` when the password clears every hard rule **and** its strength score meets the minimum, or `{:rejected, score, reasons}`, where `reasons` is a list of atoms describing every reason the password was rejected (all applicable reasons are reported, not just the first). `score` is always the computed integer strength score and is present in both the accepted and the rejected result.

### The `context` argument

The `context` argument is a map that supplies configuration and per-user data:

- `:username` (required) — the username the password is being set for. If the context map does not include `:username`, `evaluate/2` must raise an `ArgumentError`.
- `:min_length` (optional, default `8`) — a *hard* minimum; shorter passwords are rejected with `:too_short` regardless of score.
- `:min_score` (optional, default `60`) — the minimum strength score required; passwords scoring strictly below this value are rejected with `:insufficient_strength`.
- `:common_passwords` (optional, default `[]`) — a list of plaintext strings considered too common; a case-insensitive match is a hard rejection with `:common_password`.
- `:max_username_similarity` (optional, default `3`) — the password is rejected with `:too_similar_to_username` if its Levenshtein distance from the username (compared case-insensitively) is less than or equal to this value.

## Scoring model

The strength score is computed deterministically as the sum, capped at `100`, of the following components:

- **Length points:** `2` points per character, counting at most `20` characters (so `0`–`40`).
- **Character-class points:** `10` points for each of the following classes present at least once — uppercase ASCII letter, lowercase ASCII letter, digit, and non-alphanumeric ("special") character (so `0`–`40`).
- **Length bonus:** a flat `20` points if the password is at least `16` characters long.

## Edge cases

- The rejection atoms in use are: `:too_short`, `:common_password`, `:too_similar_to_username`, `:insufficient_strength`. When multiple apply, they are listed in that canonical order.
- A missing `:username` key in `context` raises an `ArgumentError`.
- Common-password matching is case-insensitive; username-similarity comparison is likewise case-insensitive.
- A password shorter than `:min_length` is rejected with `:too_short` no matter how it scores.
- A score strictly below `:min_score` yields `:insufficient_strength`.
- A Levenshtein distance from the username less than or equal to `:max_username_similarity` yields `:too_similar_to_username`.
