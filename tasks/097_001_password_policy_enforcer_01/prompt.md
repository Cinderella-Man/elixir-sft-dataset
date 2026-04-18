Write me an Elixir module called `PasswordPolicy` that validates passwords against a configurable set of rules.

I need a single public function:
- `PasswordPolicy.validate(password, context)` which returns `:ok` if the password passes all active rules, or `{:error, violations}` where `violations` is a list of atoms describing every rule that failed (all violations must be reported, not just the first one).

The `context` argument is a map that drives both configuration and per-user data. It supports the following keys:
- `:username` (required) — the username the password is being set for.
- `:min_length` (optional, default `8`) — minimum number of characters.
- `:max_length` (optional, default `128`) — maximum number of characters.
- `:require_uppercase` (optional, default `true`) — must contain at least one uppercase ASCII letter.
- `:require_lowercase` (optional, default `true`) — must contain at least one lowercase ASCII letter.
- `:require_digit` (optional, default `true`) — must contain at least one digit.
- `:require_special` (optional, default `true`) — must contain at least one character that is not alphanumeric.
- `:common_passwords` (optional, default `[]`) — a list of plaintext strings considered too common; the password must not appear in this list (case-insensitive comparison).
- `:previous_passwords` (optional, default `[]`) — a list of previously used plaintext passwords; the new password must not match any of them exactly.
- `:max_username_similarity` (optional, default `3`) — the password is rejected if its Levenshtein distance from the username is less than or equal to this value (i.e. distance must be strictly greater than this threshold).

The violation atoms to use are: `:too_short`, `:too_long`, `:no_uppercase`, `:no_lowercase`, `:no_digit`, `:no_special`, `:common_password`, `:reused_password`, `:too_similar_to_username`.

Implement Levenshtein distance yourself using dynamic programming — do not use any external library. All other logic must also use only the Elixir/OTP standard library with no external dependencies.

Give me the complete module in a single file.