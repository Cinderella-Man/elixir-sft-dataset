Write me an Elixir module called `TOTPVault` that is a `GenServer` managing per-account TOTP secrets and validating codes with **replay protection**, using only the OTP standard library — no external dependencies.

The point of this variant is state and concurrency: a single server process holds every account's secret and the highest 30-second step that has already been "spent." Once a code for a given step is consumed, that same code (and any code for an earlier step) can never be accepted again, even under concurrent submissions.

Codes are standard RFC 6238: base32 secret (160 bits / 20 random bytes, no padding, generated with `:crypto.strong_rand_bytes/1`), HMAC-SHA1 over the big-endian 8-byte step `div(time, 30)`, RFC 4226 dynamic truncation, modulo 1_000_000, left-padded to a 6-character string.

I need these functions in the public API:

- `TOTPVault.start_link(opts \\ [])` starts the server and returns `{:ok, pid}`. It accepts a standard `:name` option for registering the process.
- `TOTPVault.register(server, account_id)` generates a fresh secret for `account_id`, stores it, and returns `{:ok, secret}` (the base32 secret string). If `account_id` is already registered, it returns `{:error, :already_registered}` and does not change the stored secret.
- `TOTPVault.secret(server, account_id)` returns `{:ok, secret}` for a registered account, or `{:error, :not_found}`.
- `TOTPVault.current_code(server, account_id, opts \\ [])` returns `{:ok, code}` — the 6-digit code for the account at the given time — or `{:error, :not_found}`. It accepts a `:time` option (UNIX seconds, default: current time). This function is read-only: it never consumes anything.
- `TOTPVault.consume(server, account_id, code, opts \\ [])` validates and, on success, spends a code. Options:
  - `:time` — UNIX seconds (default: current time)
  - `:window` — number of 30-second steps accepted in each direction (default: `1`)

  Let `base = div(time, 30)`. Consider the steps `base - window .. base + window` (only those `>= 0`). Behavior:
  - If `account_id` is not registered, return `{:error, :not_found}`.
  - If `code` (accepted as a string or integer) does not match the code for any step in the window, return `{:error, :invalid}`.
  - If `code` matches a step in the window, let `matched` be that step. If the account already has a consumed step `last` and `matched <= last`, return `{:error, :replayed}` and do not change stored state.
  - Otherwise (a match with `matched` greater than any previously consumed step, or no prior consumption), record `matched` as the account's new highest consumed step and return `:ok`.

Concurrency requirement: because the server processes messages one at a time, if several callers submit the *same* valid code concurrently, exactly one `consume/4` call returns `:ok` and every other returns `{:error, :replayed}`.

Requirements and constraints:
- Base32 encoding/decoding must follow RFC 4648 (uppercase alphabet A–Z, 2–7, unpadded). Implement it yourself.
- HMAC-SHA1 must be done via Erlang's `:crypto.mac/4`.
- Dynamic truncation: last byte masked with `0x0F` is the offset; read 4 bytes from that offset; mask the top bit with `0x7F`; take modulo 1_000_000.
- Generated codes are always exactly 6 characters, zero-padded.

Give me the complete module in a single file.