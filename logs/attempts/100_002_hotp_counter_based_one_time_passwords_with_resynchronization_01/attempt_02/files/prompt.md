Write me an Elixir module called `HOTP` that implements RFC 4226 HMAC-Based (counter-based) One-Time Passwords using only the OTP standard library — no external dependencies.

Unlike time-based codes, HOTP codes are driven by a monotonically increasing **counter** that both sides advance on each successful authentication. Because the client's counter can run ahead of the server's (a button pressed without a successful login), the server validates with a bounded **look-ahead** window and resynchronizes to whatever counter actually matched.

I need these functions in the public API:

- `HOTP.generate_secret()` returns a cryptographically random, base32-encoded secret string (160 bits / 20 bytes of entropy, no padding characters). It must use `:crypto.strong_rand_bytes/1`.
- `HOTP.generate_code(secret, counter)` returns a 6-digit zero-padded string for a non-negative integer `counter`. It must HMAC-SHA1 the counter (encoded as a big-endian 8-byte integer) with the base32-decoded secret, apply the RFC 4226 dynamic truncation, and take the result modulo 1_000_000.
- `HOTP.valid?(secret, code, counter, opts \\ [])` validates a `code` (string or integer) against `secret`. It accepts a `:look_ahead` option (non-negative integer, default `0`) giving how many additional counters *after* `counter` to also accept. It returns `true` if `code` matches the code for any counter in the inclusive range `counter..(counter + look_ahead)`, and `false` otherwise.
- `HOTP.verify(secret, code, counter, opts \\ [])` performs resynchronizing validation. It accepts a `:look_ahead` option (non-negative integer, default `3`). Searching counters in ascending order across the inclusive range `counter..(counter + look_ahead)`, it returns `{:ok, matched_counter + 1}` for the first counter whose code matches (the returned value is the next counter the server should store), or `:error` if no counter in the range matches.
- `HOTP.provisioning_uri(secret, issuer, account_name, counter)` returns an `otpauth://hotp/` URI with the label `issuer:account_name` (both URI-encoded) and query parameters `secret`, `issuer`, `algorithm=SHA1`, `digits=6`, and `counter=<counter>` — all properly URI-encoded.

Requirements and constraints:
- Base32 encoding/decoding must follow RFC 4648 (uppercase alphabet A–Z, 2–7, unpadded). Implement it yourself rather than relying on a library.
- HMAC-SHA1 must be done via Erlang's `:crypto.mac/4`.
- Dynamic truncation: take the last byte of the HMAC, mask with `0x0F` to get the offset, then read 4 bytes from that offset, mask the top bit with `0x7F`, and take the result modulo 1_000_000.
- The generated code must always be exactly 6 characters, left-padded with zeros if necessary.

Give me the complete module in a single file.