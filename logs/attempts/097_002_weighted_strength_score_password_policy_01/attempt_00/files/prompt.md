Write me an Elixir module called `PasswordPolicy` that scores password *strength* on a 0–100 scale and accepts or rejects based on a configurable threshold, rather than treating every rule as an equal pass/fail gate.

I need a single public function:
- `PasswordPolicy.evaluate(password, context)` which returns `{:accepted, score}` when the password clears every hard rule **and** its strength score meets the minimum, or `{:rejected, score, reasons}` where `reasons` is a list of atoms describing every reason the password was rejected (report all of them, not just the first). `score` is always the computed integer strength score, present in both the accepted and rejected results.

The `context` argument is a map that drives configuration and per-user data:
- `:username` (required) — the username the password is being set for.
- `:min_length` (optional, default `8`) — a *hard* minimum; shorter passwords are rejected with `:too_short` regardless of score.
- `:min_score` (optional, default `60`) — the minimum strength score required; passwords scoring strictly below this are rejected with `:insufficient_strength`.
- `:common_passwords` (optional, default `[]`) — a list of plaintext strings considered too common; a case-insensitive match is a hard rejection with `:common_password`.
- `:max_username_similarity` (optional, default `3`) — the password is rejected with `:too_similar_to_username` if its Levenshtein distance from the username (compared case-insensitively) is less than or equal to this value.

The strength score is computed deterministically as the sum (capped at `100`) of:
- **Length points:** `2` points per character, counting at most `20` characters (so `0`–`40`).
- **Character-class points:** `10` points for each of the following classes present at least once — uppercase ASCII letter, lowercase ASCII letter, digit, and non-alphanumeric ("special") character (so `0`–`40`).
- **Length bonus:** a flat `20` points if the password is at least `16` characters long.

The rejection atoms to use are: `:too_short`, `:common_password`, `:too_similar_to_username`, `:insufficient_strength`. When multiple apply, list them in that canonical order.

Implement Levenshtein distance yourself using dynamic programming — do not use any external library. All other logic must also use only the Elixir/OTP standard library with no external dependencies.

Give me the complete module in a single file.