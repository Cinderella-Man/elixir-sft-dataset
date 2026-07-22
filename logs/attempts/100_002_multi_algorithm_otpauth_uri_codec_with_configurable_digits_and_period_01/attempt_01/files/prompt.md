Write me an Elixir module called `OTPAuth` that implements a **multi-algorithm, configuration-driven** one-time-password codec: RFC 6238 TOTP code generation plus a full `otpauth://` provisioning-URI **codec** (build *and* parse). Use only the Erlang/OTP + Elixir standard libraries — no external dependencies, and do not use `Base.encode32/2` or `Base.decode32/2`; write the base32 layer yourself.

Unlike a fixed SHA1 / 6-digit / 30-second implementation, every knob here is part of a **config map** that can be produced by parsing a URI supplied by a third party, so parsing is where the failure semantics live: parsing never raises, it returns tagged error tuples.

## The config map

A config is a plain map with these keys:

* `:secret` — base32 secret string (required)
* `:issuer` — string (required by `build_uri/1`)
* `:account_name` — string (required by `build_uri/1`)
* `:algorithm` — `:sha1` | `:sha256` | `:sha512` (optional, defaults to `:sha1`)
* `:digits` — `6`, `7`, or `8` (optional, defaults to `6`)
* `:period` — positive integer seconds (optional, defaults to `30`)

`generate_code/2` and `valid?/3` only need `:secret`; any of `:algorithm`, `:digits`, `:period` that are absent from the map take the defaults above.

## Public API

### `OTPAuth.generate_secret(bytes \\ 20)`

Returns a cryptographically random, unpadded, uppercase base32 string encoding `bytes` bytes of entropy (default 20 = 160 bits). Must use `:crypto.strong_rand_bytes/1`. The result must match `~r/\A[A-Z2-7]+\z/`.

### `OTPAuth.decode_secret(secret)`

Returns `{:ok, binary}` or `{:error, :invalid_secret}`.

Decoding is **lenient about presentation** and follows RFC 4648 base32 (alphabet `A`–`Z`, `2`–`7`):

* lowercase letters are accepted (upcased first),
* ASCII whitespace is ignored (authenticator apps display secrets in space-separated groups),
* trailing `=` padding characters are ignored,
* leftover bits that do not complete a byte are discarded.

Any other character, or a secret that normalizes to fewer than 8 bits of data (e.g. the empty string), yields `{:error, :invalid_secret}`.

### `OTPAuth.generate_code(config, time \\ :os.system_time(:second))`

Returns the zero-padded decimal code string for the given UNIX timestamp:

* time step is `div(time, period)`, encoded as a big-endian unsigned 64-bit integer,
* HMAC of that counter with the decoded secret under the configured hash, via `:crypto.mac(:hmac, algorithm, key, counter)`,
* RFC 4226 §5.3 dynamic truncation: `offset = last_byte &&& 0x0F`, read the 4 bytes at `offset`, mask the top bit of the first with `0x7F`, combine big-endian,
* take the result modulo `10^digits` and left-pad with zeros to exactly `digits` characters.

The returned string is always exactly `digits` characters long and matches `~r/\A\d+\z/`.

If `config.secret` is not valid base32, `generate_code/2` raises `ArgumentError`.

### `OTPAuth.valid?(config, code, opts \\ [])`

Validates a code given as a string or an integer (an integer is zero-padded to `digits` before comparison). Options:

* `:time` — UNIX seconds to validate against (default: current system time),
* `:window` — number of steps of `config.period` accepted in **each** direction (default: `1`).

Returns `true` if the code equals the code generated at any step in `time - window*period .. time + window*period`, `false` otherwise. `window: 0` accepts only the exact current step. The comparison must be constant-time with respect to matching-prefix length (compare all bytes, no early exit).

### `OTPAuth.build_uri(config)`

Returns an `otpauth://totp/` URI:

* label is `issuer:account_name`, each side URI-encoded (unreserved characters only),
* query string, in this exact key order: `secret`, `issuer`, `algorithm`, `digits`, `period`, built with `URI.encode_query/1`,
* `algorithm` is emitted uppercase: `SHA1`, `SHA256` or `SHA512`,
* `digits` and `period` are emitted as decimal strings,
* defaults are materialized: a config without `:algorithm` / `:digits` / `:period` still emits `algorithm=SHA1`, `digits=6`, `period=30`.

### `OTPAuth.parse_uri(uri)`

Returns `{:ok, config}` or `{:error, reason}`. It must **never raise** on malformed input. The returned config always has all six keys populated (defaults filled in), and `:secret` is normalized — upcased, with whitespace and `=` padding removed.

Validation happens in exactly this order, returning the first failure:

1. scheme must be `otpauth` → else `{:error, :invalid_scheme}`
2. host must be `totp` → else `{:error, :unsupported_type}`
3. the path must contain a non-empty label after the leading `/` → else `{:error, :invalid_label}`. The label is percent-decoded. If it contains a `:`, it splits at the **first** colon into a label-issuer and the account name, and leading spaces are trimmed from the account name (so `Acme:%20alice` yields account `"alice"`). If it contains no colon, the whole label is the account name and there is no label-issuer.
4. a `secret` query parameter must be present → else `{:error, :missing_secret}`
5. the secret must decode per `decode_secret/1` → else `{:error, :invalid_secret}`
6. if both a label-issuer and an `issuer` query parameter are present and they differ, `{:error, :issuer_mismatch}`. Otherwise the issuer is the `issuer` query parameter if present, else the label-issuer if present, else `""`.
7. `algorithm` (case-insensitive `sha1` / `sha256` / `sha512`, absent ⇒ `:sha1`) → else `{:error, :unsupported_algorithm}`
8. `digits` must be the decimal string `6`, `7`, or `8` (absent ⇒ `6`) → else `{:error, :invalid_digits}`
9. `period` must be a decimal string for a positive integer (absent ⇒ `30`) → else `{:error, :invalid_period}`

`parse_uri(build_uri(config))` must round-trip a fully populated config back to an equal map.

Give me the complete module in a single file.