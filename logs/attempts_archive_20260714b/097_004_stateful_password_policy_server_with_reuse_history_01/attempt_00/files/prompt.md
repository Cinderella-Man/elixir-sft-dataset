Write me an Elixir module called `PasswordPolicy` implemented as a **GenServer** that enforces a password policy *and* remembers each user's recent passwords so it can reject reuse across changes over time.

The server is configured once at startup and then services password-change requests for many users, keeping a bounded per-user history of previously accepted passwords.

I need this public API:
- `PasswordPolicy.start_link(opts)` — starts the server. `opts` is a keyword list carrying the policy configuration and:
  - `:name` (optional) — if given, registers the server under that name.
  - `:history_size` (optional, default `5`) — how many of each user's most recently accepted passwords to remember and forbid reusing.
  - Policy keys (all optional, same defaults as below): `:min_length` (`8`), `:max_length` (`128`), `:require_uppercase` (`true`), `:require_lowercase` (`true`), `:require_digit` (`true`), `:require_special` (`true`), `:common_passwords` (`[]`), `:max_username_similarity` (`3`).
- `PasswordPolicy.set_password(server, username, password)` — validates `password` for `username` against the policy and against that user's remembered history. Returns `:ok` when it passes every rule (and, as a side effect, records the password at the front of the user's history, evicting the oldest beyond `:history_size`). Returns `{:error, violations}` — a list of every failing rule atom — otherwise, and in that case the history is **not** modified.
- `PasswordPolicy.history_count(server, username)` — returns the number of passwords currently remembered for `username` (`0` if the user is unknown).

Validation rules and their violation atoms:
- `:too_short` / `:too_long` — length outside `[min_length, max_length]`.
- `:no_uppercase`, `:no_lowercase`, `:no_digit`, `:no_special` — the corresponding required character class is missing (a "special" character is any non-alphanumeric character). Skip the check when its `:require_*` option is `false`.
- `:common_password` — the password matches any entry in `:common_passwords` (case-insensitive).
- `:reused_password` — the password exactly matches any password currently in that user's remembered history.
- `:too_similar_to_username` — the password's Levenshtein distance from the username (compared case-insensitively) is less than or equal to `:max_username_similarity`.

Report all violations, in this canonical order: `:too_short`, `:too_long`, `:no_uppercase`, `:no_lowercase`, `:no_digit`, `:no_special`, `:common_password`, `:reused_password`, `:too_similar_to_username`. Per-user histories must be independent.

Implement Levenshtein distance yourself using dynamic programming — do not use any external library. All other logic must also use only the Elixir/OTP standard library with no external dependencies.

Give me the complete module in a single file.