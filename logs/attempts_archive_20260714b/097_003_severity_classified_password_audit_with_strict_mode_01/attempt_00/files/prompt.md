Write me an Elixir module called `PasswordPolicy` that audits a password and classifies each failing rule by severity, distinguishing blocking **errors** from non-blocking **warnings**.

I need a single public function:
- `PasswordPolicy.audit(password, context)` which returns a report map of the shape `%{status: :ok | :error, errors: [atom()], warnings: [atom()]}`. `errors` lists every blocking violation, `warnings` lists every advisory violation, and `status` is `:error` when there is at least one error and `:ok` otherwise (warnings alone never change the status to `:error`). Report all violations, not just the first.

Rules are split into two severities:
- **Errors (blocking):** minimum length (`:too_short`), maximum length (`:too_long`), common-password blocklist (`:common_password`), and previously-used-password reuse (`:reused_password`).
- **Warnings (advisory):** missing uppercase (`:no_uppercase`), missing lowercase (`:no_lowercase`), missing digit (`:no_digit`), missing special character (`:no_special`), and being too similar to the username (`:too_similar_to_username`).

The `context` argument is a map that drives configuration and per-user data:
- `:username` (required) — the username the password is being set for.
- `:min_length` (optional, default `8`) — minimum number of characters.
- `:max_length` (optional, default `128`) — maximum number of characters.
- `:require_uppercase` (optional, default `true`) — must contain at least one uppercase ASCII letter.
- `:require_lowercase` (optional, default `true`) — must contain at least one lowercase ASCII letter.
- `:require_digit` (optional, default `true`) — must contain at least one digit.
- `:require_special` (optional, default `true`) — must contain at least one non-alphanumeric character.
- `:common_passwords` (optional, default `[]`) — plaintext strings considered too common; the password must not match any (case-insensitive comparison).
- `:previous_passwords` (optional, default `[]`) — previously used plaintext passwords; the new password must not match any exactly.
- `:max_username_similarity` (optional, default `3`) — the password triggers the similarity warning if its Levenshtein distance from the username (compared case-insensitively) is less than or equal to this value.
- `:strict` (optional, default `false`) — when `true`, every warning is *promoted* to an error: the `warnings` list is emptied, all violations appear in `errors`, and any violation at all forces `status: :error`.

Both `errors` and `warnings` must be listed in this canonical rule order: `:too_short`, `:too_long`, `:no_uppercase`, `:no_lowercase`, `:no_digit`, `:no_special`, `:common_password`, `:reused_password`, `:too_similar_to_username`.

Implement Levenshtein distance yourself using dynamic programming — do not use any external library. All other logic must also use only the Elixir/OTP standard library with no external dependencies.

Give me the complete module in a single file.