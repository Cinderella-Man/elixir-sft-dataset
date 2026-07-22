Write me an Elixir module called `TOTP` that implements RFC 6238 Time-Based One-Time Passwords (TOTP) using only the OTP standard library — no external dependencies.

I need these functions in the public API:

- `TOTP.generate_secret()` returns a cryptographically random, base32-encoded secret string (160 bits / 20 bytes of entropy, no padding characters).
- `TOTP.generate_code(secret, time \\ :os.system_time(:second))` returns a 6-digit zero-padded string for the given UNIX timestamp. It should derive the time step as `div(time, 30)`, HMAC-SHA1 the step (as a big-endian 8-byte integer) with the base32-decoded secret, apply the RFC 4226 dynamic truncation, and take the result modulo 1_000_000.
- `TOTP.valid?(secret, code, opts \\ [])` validates a code string or integer against the current time. It must accept a `:time` option (UNIX seconds, defaults to now) and a `:window` option (integer number of steps to check in each direction, defaults to 1) so that clock drift of up to ±30 seconds is tolerated. Return `true` if the code matches any step in the window, `false` otherwise.
- `TOTP.provisioning_uri(secret, issuer, account_name)` returns an `otpauth://totp/` URI with the label `issuer:account_name` and query parameters `secret`, `issuer`, `algorithm=SHA1`, `digits=6`, and `period=30` — all properly URI-encoded.

Requirements and constraints:
- Base32 encoding/decoding must follow RFC 4648 (uppercase alphabet A–Z, 2–7). Implement it yourself rather than relying on a library.
- HMAC-SHA1 must be done via Erlang's `:crypto.mac/4`.
- Dynamic truncation: take the last byte of the HMAC, mask with `0x0F` to get the offset, then read 4 bytes from that offset, mask the top bit with `0x7F`, and take the result modulo 1_000_000.
- The generated code must always be exactly 6 characters, left-padded with zeros if necessary.
- `generate_secret/0` must use `:crypto.strong_rand_bytes/1`.

Give me the complete module in a single file.