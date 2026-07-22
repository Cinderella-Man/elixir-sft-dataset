Write me an Elixir module called `TOTP` that implements a **configurable, multi-algorithm** RFC 6238 Time-Based One-Time Password generator using only the OTP standard library (no external dependencies). Unlike a fixed SHA1/6-digit/30-second implementation, every parameter — hash algorithm, digit count, and period — is caller-configurable through options, and the module can both emit and parse `otpauth://totp/` provisioning URIs.

I need these functions in the public API:

- `TOTP.generate_secret(opts \\ [])` returns a cryptographically random, base32-encoded secret string (RFC 4648 uppercase alphabet A–Z, 2–7, no padding). Option `:bytes` sets the entropy in bytes (default `20`, i.e. 160 bits → a 32-character secret). Must use `:crypto.strong_rand_bytes/1`.

- `TOTP.generate_code(secret, opts \\ [])` returns a zero-padded numeric string. Options:
  - `:time` — UNIX seconds (default: current time).
  - `:algorithm` — one of `:sha1`, `:sha256`, `:sha512` (default `:sha1`).
  - `:digits` — number of digits in the code (default `6`).
  - `:period` — step length in seconds (default `30`).

  It derives the time step as `div(time, period)`, HMACs that step (as a big-endian 8-byte unsigned integer) using the chosen algorithm with the base32-decoded secret, applies the RFC 4226 dynamic truncation, takes the result modulo `10^digits`, and left-pads with zeros to exactly `digits` characters. Because the algorithm is fully specified, SHA1 codes match the standard RFC 6238 test vectors for the secret `"12345678901234567890"` (base32 `GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ`): at `t = 59` the 8-digit code is `94287082` (and the 6-digit code is `287082`).

- `TOTP.valid?(secret, code, opts \\ [])` validates a code (string or integer; integers are zero-padded to `:digits` characters) against the current time, tolerating clock drift. It accepts `:time`, `:window` (integer number of steps checked in each direction, default `1`), plus the same `:algorithm`, `:digits`, and `:period` options as `generate_code/2` (with the same defaults). It returns `true` if the code matches the code computed at any step in `-window..window` (using the configured algorithm, digits, and period), `false` otherwise.

- `TOTP.provisioning_uri(secret, issuer, account_name, opts \\ [])` returns an `otpauth://totp/` URI with the label `issuer:account_name` (URI-encoded) and query parameters `secret`, `issuer`, `algorithm`, `digits`, and `period`. The `:algorithm`, `:digits`, and `:period` options (same defaults as above) are reflected in the query: `algorithm` is the uppercase name (`SHA1`, `SHA256`, or `SHA512`), `digits` and `period` are their decimal integers.

- `TOTP.parse_uri(uri)` parses an `otpauth://totp/` provisioning URI and returns `{:ok, config}` where `config` is a map with keys `:secret` (string), `:issuer` (string or `nil`), `:algorithm` (`:sha1`/`:sha256`/`:sha512`), `:digits` (integer), and `:period` (integer). A missing `algorithm` defaults to `:sha1`, a missing `digits` to `6`, and a missing `period` to `30`. It returns `:error` if the scheme is not `otpauth`, the host is not `totp`, or there is no query string.

Requirements and constraints:
- Base32 encoding/decoding must follow RFC 4648 and be implemented yourself, not via a library.
- HMAC must be done via Erlang's `:crypto.mac/4` with the algorithm selected by the `:algorithm` option (`:sha1` maps to Erlang's `:sha`).
- Dynamic truncation (RFC 4226 §5.3): take the last byte of the HMAC, mask with `0x0F` to get the offset, read 4 bytes from that offset, mask the top bit of the first byte with `0x7F`, combine as a 31-bit big-endian integer, then take modulo `10^digits`.

Give me the complete module in a single file.