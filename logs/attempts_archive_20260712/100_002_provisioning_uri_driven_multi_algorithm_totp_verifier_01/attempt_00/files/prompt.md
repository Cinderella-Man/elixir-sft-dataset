Write me an Elixir module called `AuthenticatorURI` that goes the *other* direction from a normal TOTP generator: instead of building an `otpauth://` provisioning URI, it **parses** one into a validated configuration and then generates/verifies codes from that configuration. Use only the OTP standard library — no external dependencies.

The point of the module is that authenticator apps must accept whatever the server put in the QR code: SHA1/SHA256/SHA512, 6/7/8 digits, and periods other than 30 seconds. So all OTP parameters come from the URI, not from hard-coded constants.

## Public API

### `AuthenticatorURI.parse(uri)`

Takes an `otpauth://totp/...` URI string and returns `{:ok, config}` or `{:error, reason}` where `reason` is an atom.

`config` is a map with exactly these keys:

- `:issuer` — `String.t()` or `nil`
- `:account` — `String.t()`
- `:secret` — `String.t()` (normalized base32, see below)
- `:algorithm` — `:sha1`, `:sha256`, or `:sha512`
- `:digits` — integer, one of `6`, `7`, `8`
- `:period` — positive integer (seconds)

Parsing rules:

- **Scheme.** The scheme must be `otpauth` (compare case-insensitively). Anything else — and any non-binary argument — returns `{:error, :invalid_scheme}`.
- **Type.** The URI host is the OTP type. It must be `totp` (case-insensitive). `hotp` or anything else returns `{:error, :unsupported_type}`.
- **Label.** The path (with its leading `/` removed) is the percent-encoded label. Decode it with `URI.decode/1`. It is either `Issuer:Account` or just `Account`. A single optional space immediately after the colon is allowed and must be stripped from the account. An empty label, an empty issuer part, or an empty account part returns `{:error, :missing_label}`.
- **Query parameters.** Decode with `URI.decode_query/1` (so `+` means space).
  - `secret` (required). Strip all whitespace and `=` padding characters, then upcase. After that it must be a non-empty string of RFC 4648 base32 characters (`A`–`Z`, `2`–`7`); the normalized string is what goes into `config.secret`. A missing `secret` returns `{:error, :missing_secret}`; a secret with any other character (or one that normalizes to the empty string) returns `{:error, :invalid_secret}`.
  - `issuer` (optional). If the label carries an issuer and the `issuer` parameter is also present, they must be equal — otherwise return `{:error, :issuer_mismatch}`. If only one of them is present, that one is the issuer. If neither is present, `config.issuer` is `nil`.
  - `algorithm` (optional, default `SHA1`). Case-insensitive; `SHA1` → `:sha1`, `SHA256` → `:sha256`, `SHA512` → `:sha512`. Anything else returns `{:error, :unsupported_algorithm}`.
  - `digits` (optional, default `6`). Must be the exact decimal string of `6`, `7`, or `8`; anything else (including non-numeric text or trailing garbage) returns `{:error, :invalid_digits}`.
  - `period` (optional, default `30`). Must be the exact decimal string of a positive integer; zero, negative, or non-numeric values return `{:error, :invalid_period}`.

### `AuthenticatorURI.code_at(config, unix_time)`

Returns the OTP code for a parsed `config` at the given UNIX timestamp (seconds), as a zero-padded string of exactly `config.digits` characters.

Algorithm (RFC 6238 / RFC 4226):

1. `step = div(unix_time, config.period)`, encoded as a big-endian unsigned 64-bit integer.
2. HMAC that counter with the base32-decoded secret using `:crypto.mac(:hmac, hash, key, counter)`, where `hash` is `:sha`, `:sha256`, or `:sha512` according to `config.algorithm`.
3. Dynamic truncation: take the low 4 bits of the **last** byte of the HMAC as an offset, read the 4 bytes at that offset, mask the top bit of the first of them with `0x7F`, and interpret them big-endian.
4. Take the result modulo `10 ^ config.digits` and zero-pad on the left to `config.digits` characters.

You must implement RFC 4648 base32 **decoding** yourself (uppercase alphabet `A`–`Z` plus `2`–`7`, no padding; leftover bits that do not complete a byte are discarded). Do not use an external library.

### `AuthenticatorURI.seconds_remaining(config, unix_time)`

Returns `config.period - rem(unix_time, config.period)` — i.e. the number of seconds the current code stays valid. On an exact period boundary this returns the full period.

### `AuthenticatorURI.verify(config, code, unix_time)`

Returns `true` if `code` matches the code for the *exact* current step, `false` otherwise. There is **no** drift window: a code from the previous or next step must be rejected. `code` may be a string or an integer; normalize it by converting to a string and zero-padding on the left to `config.digits` characters, then compare against `code_at/2` using a constant-time (non-short-circuiting) byte comparison.

Give me the complete module in a single file.