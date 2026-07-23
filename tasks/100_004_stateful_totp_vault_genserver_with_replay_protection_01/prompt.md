# TOTPVault — stateful TOTP vault with replay protection

**Summary:** Implement an Elixir module `TOTPVault`, a `GenServer` that manages per-account TOTP secrets and validates codes with replay protection. OTP standard library only — no external dependencies. Deliver the complete module in a single file.

**State model**
- A single server process holds every account's secret plus the highest 30-second step already "spent" for that account.
- Once a code for a given step is consumed, that same code — and any code for an earlier step — must never be accepted again, including under concurrent submissions.

**Code derivation (RFC 6238)**
- Secret: base32, 160 bits / 20 random bytes, no padding, generated with `:crypto.strong_rand_bytes/1`.
- HMAC-SHA1 over the big-endian 8-byte step `div(time, 30)`.
- RFC 4226 dynamic truncation, modulo 1_000_000, left-padded to a 6-character string.

**Public API**
- `TOTPVault.start_link(opts \\ [])` — starts the server, returns `{:ok, pid}`. Accepts the standard `:name` option for registering the process.
- `TOTPVault.register(server, account_id)` — generates a fresh secret for `account_id`, stores it, returns `{:ok, secret}` (the base32 secret string). If `account_id` is already registered, returns `{:error, :already_registered}` and leaves the stored secret unchanged.
- `TOTPVault.secret(server, account_id)` — returns `{:ok, secret}` for a registered account, else `{:error, :not_found}`.
- `TOTPVault.current_code(server, account_id, opts \\ [])` — returns `{:ok, code}`, the 6-digit code for the account at the given time, or `{:error, :not_found}`. Accepts a `:time` option (UNIX seconds, default: current time). Read-only: never consumes anything.
- `TOTPVault.consume(server, account_id, code, opts \\ [])` — validates and, on success, spends a code. Options: `:time` (UNIX seconds, default: current time); `:window` (number of 30-second steps accepted in each direction, default: `1`).

**consume/4 semantics**
- Let `base = div(time, 30)`. Consider the steps `base - window .. base + window`, restricted to those `>= 0`.
- `account_id` not registered → `{:error, :not_found}`.
- `code` (accepted as a string or integer) matches no step in the window → `{:error, :invalid}`.
- `code` matches a step in the window: let `matched` be that step. If the account already has a consumed step `last` and `matched <= last` → `{:error, :replayed}`, stored state unchanged.
- Otherwise (match with `matched` greater than any previously consumed step, or no prior consumption) → record `matched` as the account's new highest consumed step and return `:ok`.

**Concurrency**
- Because the server processes messages one at a time, when several callers submit the *same* valid code concurrently, exactly one `consume/4` call returns `:ok` and every other returns `{:error, :replayed}`.

**Implementation constraints**
- Base32 encoding/decoding must follow RFC 4648: uppercase alphabet A–Z, 2–7, unpadded. Implement it yourself.
- HMAC-SHA1 via Erlang's `:crypto.mac/4`.
- Dynamic truncation: last byte masked with `0x0F` is the offset; read 4 bytes from that offset; mask the top bit with `0x7F`; take modulo 1_000_000.
- Generated codes are always exactly 6 characters, zero-padded.
