Write me an Elixir module called `FlexTOTP` that implements a configurable RFC 6238 Time-Based One-Time Password generator/validator supporting multiple HMAC algorithms and code lengths, plus round-trip provisioning-URI parsing — using only the OTP standard library, no external dependencies.

Where the classic implementation is hard-wired to SHA1 / 6 digits / 30-second periods, this one takes those as options, and can also parse an `otpauth://` URI back into a configuration map.

I need these functions in the public API:

- `FlexTOTP.generate_secret(bytes \\ 20)` returns a cryptographically random, base32-encoded secret string (`bytes` bytes of entropy, no padding characters). It must use `:crypto.strong_rand_bytes/1`.
- `FlexTOTP.generate_code(secret, opts \\ [])` returns a zero-padded numeric code string. Options:
  - `:time` — UNIX seconds (default: `:os.system_time(:second)`)
  - `:algorithm` — one of `:sha1`, `:sha256`, `:sha512` (default: `:sha1`)
  - `:digits` — code length (default: `6`)
  - `:period` — step size in seconds (default: `30`)

  It derives the step as `div(time, period)`, HMACs the step (as a big-endian 8-byte integer) with the base32-decoded secret using the chosen algorithm, applies RFC 4226 dynamic truncation, takes the result modulo `10^digits`, and left-pads with zeros to exactly `digits` characters.
- `FlexTOTP.valid?(secret, code, opts \\ [])` validates a `code` (string or integer) against the current time. It accepts the same `:time`, `:algorithm`, `:digits`, and `:period` options as `generate_code/2`, plus a `:window` option (integer number of steps to check in each direction, default `1`). It returns `true` if the code matches any step within `±window`, `false` otherwise.
- `FlexTOTP.provisioning_uri(secret, issuer, account_name, opts \\ [])` returns an `otpauth://totp/` URI with the label `issuer:account_name` (both URI-encoded) and query parameters `secret`, `issuer`, `algorithm`, `digits`, and `period`. The `algorithm` value is the uppercase name: `SHA1`, `SHA256`, or `SHA512` (default `SHA1`). `:digits` defaults to `6` and `:period` defaults to `30`.
- `FlexTOTP.parse_uri(uri)` parses a provisioning URI. On success it returns `{:ok, map}` where `map` has the keys:
  - `:type` — the URI host as a string (`"totp"`)
  - `:issuer` — from the `issuer` query parameter (a string), falling back to the issuer portion of the label if the query parameter is absent
  - `:account_name` — the portion of the (URI-decoded) label after the first `":"`, or the whole label if there is no colon
  - `:secret` — the `secret` query parameter (a string)
  - `:algorithm` — `:sha1`, `:sha256`, or `:sha512` parsed from the `algorithm` query parameter (defaulting to `:sha1` when absent)
  - `:digits` — integer parsed from the `digits` query parameter (defaulting to `6`)
  - `:period` — integer parsed from the `period` query parameter (defaulting to `30`)

  For any string that is not an `otpauth://` URI, it returns `:error`.

Requirements and constraints:
- Base32 encoding/decoding must follow RFC 4648 (uppercase alphabet A–Z, 2–7, unpadded). Implement it yourself rather than relying on a library.
- HMAC must be done via Erlang's `:crypto.mac/4` with `:sha`, `:sha256`, or `:sha512` selected from the `:algorithm` option.
- Dynamic truncation (must work for any HMAC length): take the last byte of the HMAC, mask with `0x0F` to get the offset, read 4 bytes from that offset, mask the top bit with `0x7F`, then take the result modulo `10^digits`.

Give me the complete module in a single file.