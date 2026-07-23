Hey — I need you to write me an Elixir module called `Anonymizer`. The job it does is anonymize fields inside deeply nested record maps, and the twist is that I want to address those fields by string paths rather than flat top-level keys.

The public API I'm after is one function: `Anonymizer.anonymize(records, rules)`. Here `records` is a list of (possibly deeply nested) maps, and `rules` is a map whose keys are string paths and whose values are one of the following rule atoms or tuples:

- `:hash` — replace the value with its SHA-256 digest encoded as a lower-case hexadecimal string.
- `:mask` — keep the first and last character of the string, replace every middle character with `*`. A string of 2 characters shows both with no masking. A string of 1 character is fully masked as `*`.
- `:redact` — replace the value with the string `"[REDACTED]"`.
- `{:fake, seed}` — generate a deterministic fake value (a realistic-looking but fabricated string) derived solely from the original value and the given `seed`. The same input value + seed must always produce the same fake output across calls.

For the path syntax, here's what I mean: dot notation descends into nested maps, so `"user.email"` targets `record[:user][:email]`. A segment ending in `[]` descends into every element of a list — so `"orders[].card"` applies the rule to the `:card` field of every element of the `:orders` list, and `"tags[]"` applies the rule to every scalar element of the `:tags` list. Keep in mind that map keys may be atoms or strings, and a path segment must match whichever the record actually uses.

The function should return a list of maps of the same length and structure, with the addressed values transformed in place. Anything not addressed by a path must be left untouched. And a path that doesn't resolve in a given record (missing key, or a type mismatch such as trying to descend into a non-map) must be skipped gracefully rather than raising.

One more thing that's important to me: referential integrity has to be preserved across the entire list. If two locations (in the same or different records) hold the same original value for paths that share a rule, their anonymized outputs must be identical — and this must hold for all four rule types.

Please stick to the Elixir/OTP standard library only — no external dependencies. Give me the complete module in a single file.
