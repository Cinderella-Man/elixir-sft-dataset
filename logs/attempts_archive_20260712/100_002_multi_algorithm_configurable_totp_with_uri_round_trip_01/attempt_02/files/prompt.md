Write me an Elixir module called `MultiTOTP` that implements RFC 6238 Time-Based One-Time Passwords but **generalized to be fully configurable**: it must support the SHA1, SHA256, and SHA512 HMAC algorithms, an arbitrary number of output digits, and an arbitrary time period. It must use only the OTP standard library — no external dependencies. On top of generation and validation, it must be able to **build** an `otpauth://` provisioning URI **and parse one back** into its component parameters (the inverse operation).

I need these functions in the public API:

- `MultiTOTP.generate_secret(byte_length \\ 20)` returns a cryptographically random, base32-encoded secret string built from `byte_length` bytes of entropy via `:crypto.strong_rand_bytes/1`. The encoding is RFC 4648 base32 (uppercase alphabet A–Z and 2–7) with **no padding characters**, so the length is `ceil(byte_length * 8 / 5)` characters — e.g. the default 20 bytes yields a 32-character string, and 32 bytes yields a 52-character string.

- `MultiTOTP.generate_code(secret, opts \\ [])` returns a zero-padded numeric code string. Options:
  - `:time` — UNIX seconds (default: current time).
  - `:algorithm` — one of `:sha1`, `:sha256`, `:sha512` (default: `:sha1`).
  - `:digits` — number of output digits (default: `6`).
  - `:period` — length of a time step in seconds (default: `30`).

  It derives the step as `div(time, period)`, HMACs the step (as a big-endian 8-byte integer) with the base32-decoded secret using the chosen algorithm, applies the RFC 4226 dynamic truncation, takes the result modulo `10^digits`, and left-pads with zeros to exactly `digits` characters. It must reproduce the RFC 6238 test vectors for all three algorithms. Note that because a shorter code is just the truncated integer modulo a smaller power of ten, the default 6-digit code equals the last 6 digits of the corresponding 8-digit code.

- `MultiTOTP.valid?(secret, code, opts \\ [])` validates a `code` (string or integer) against the current time. It accepts the same `:time`, `:algorithm`, `:digits`, and `:period` options as `generate_code/2`, plus a `:window` option (integer number of steps to check in each direction, default `1`). The code is normalized by left-padding to `:digits` characters. Return `true` if the code matches the code produced at any step within `±window` using the same parameters, `false` otherwise.

- `MultiTOTP.provisioning_uri(secret, issuer, account_name, opts \\ [])` returns an `otpauth://totp/` URI. The label is `issuer:account_name` with both parts URI-encoded. The query parameters are `secret`, `issuer`, `algorithm` (the uppercase name of the `:algorithm` option — `"SHA1"`, `"SHA256"`, or `"SHA512"`, default `"SHA1"`), `digits` (the `:digits` option, default `6`), and `period` (the `:period` option, default `30`). All parameters must be properly URI-encoded.

- `MultiTOTP.parse_uri(uri)` is the inverse of `provisioning_uri/4`. For a well-formed `otpauth://totp/...` URI it returns `{:ok, map}` where the map has:
  - `:secret` — the `secret` query parameter (a string, or `nil` if absent),
  - `:issuer` — the `issuer` query parameter if present, otherwise the portion of the label before the first `:` (or `nil` if the label has no `:`),
  - `:account_name` — the portion of the label after the first `:` (or the whole label if there is no `:`),
  - `:algorithm` — one of the atoms `:sha1`, `:sha256`, `:sha512` (case-insensitive; defaults to `:sha1` when the parameter is absent),
  - `:digits` — the `digits` parameter as an integer (default `6`),
  - `:period` — the `period` parameter as an integer (default `30`).

  If the `algorithm` parameter names anything other than SHA1/SHA256/SHA512, return `{:error, :unsupported_algorithm}`. If the input is not an `otpauth://totp/` URI, return `{:error, :invalid_uri}`.

Requirements and constraints:
- Base32 encoding/decoding must follow RFC 4648 (uppercase A–Z, 2–7, unpadded). Implement it yourself rather than relying on a library.
- HMAC must be done via Erlang's `:crypto.mac/4` with the appropriate hash (`:sha`, `:sha256`, `:sha512`).
- Dynamic truncation (RFC 4226 §5.3): take the last byte of the HMAC, mask with `0x0F` to get the offset, read 4 bytes from that offset, mask the top bit of the first with `0x7F`, then take the resulting 31-bit integer modulo `10^digits`. This must work for HMACs of any length (20, 32, or 64 bytes).
- `generate_secret/1` must use `:crypto.strong_rand_bytes/1`.

For reference, the RFC 6238 test vectors use these ASCII seeds (base32-encoded before being passed in): SHA1 uses `"12345678901234567890"`, SHA256 uses `"12345678901234567890123456789012"`, and SHA512 uses `"1234567890123456789012345678901234567890123456789012345678901234"`. At `t = 59` the 8-digit codes are `94287082` (SHA1), `46119246` (SHA256), and `90693936` (SHA512).

Give me the complete module in a single file.