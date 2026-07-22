Write me an Elixir module called `HOTP` that implements RFC 4226 **HMAC-based** One-Time Passwords — the counter-based sibling of TOTP. Unlike a time-based scheme, each code is tied to a monotonically increasing integer counter rather than the wall clock, and validation must support a **forward-only resynchronization window** because a client's counter can run ahead of the server's (e.g. the user generated codes that were never submitted). Use only the OTP standard library — no external dependencies.

I need these functions in the public API:

- `HOTP.generate_secret()` returns a cryptographically random, base32-encoded secret string (160 bits / 20 bytes of entropy, no padding characters), producing a 32-character string. It must use `:crypto.strong_rand_bytes/1`.

- `HOTP.generate_code(secret, counter)` returns a 6-digit zero-padded string for the given non-negative integer `counter`. It HMAC-SHA1s the counter (encoded as a big-endian 8-byte integer) with the base32-decoded secret, applies the RFC 4226 dynamic truncation, and takes the result modulo 1_000_000. The same counter with the same secret must always produce the same code. It must reproduce the RFC 4226 Appendix D test vectors for the seed `"12345678901234567890"`: counters 0 through 9 yield `755224`, `287082`, `359152`, `969429`, `338314`, `254676`, `287922`, `162583`, `399871`, `520489`.

- `HOTP.valid?(secret, code, counter, opts \\ [])` validates a `code` (string or integer) against a stored `counter`. Options:
  - `:look_ahead` — a non-negative integer (default `0`) giving how many additional counters **beyond** `counter` to try.

  Validation checks the counters `counter, counter + 1, …, counter + look_ahead` in ascending order. This is **forward-only**: counters below `counter` are never checked. If the code matches at some counter `c`, return `{:ok, c + 1}` (the next counter the server should store so the used code cannot be replayed). If no counter in the range matches, return `:error`. The code is normalized by left-padding to 6 digits before comparison. When multiple counters would match, the first (lowest) match wins.

- `HOTP.provisioning_uri(secret, issuer, account_name, counter)` returns an `otpauth://hotp/` URI (note: `hotp`, not `totp`, since HOTP authenticators require a counter). The label is `issuer:account_name` with both parts URI-encoded. The query parameters are `secret`, `issuer`, `algorithm=SHA1`, `digits=6`, and `counter` (the given integer). All parameters must be properly URI-encoded.

Requirements and constraints:
- Base32 encoding/decoding must follow RFC 4648 (uppercase alphabet A–Z, 2–7, unpadded). Implement it yourself rather than relying on a library.
- HMAC-SHA1 must be done via Erlang's `:crypto.mac/4`.
- Dynamic truncation (RFC 4226 §5.3): take the last byte of the HMAC, mask with `0x0F` to get the offset, read 4 bytes from that offset, mask the top bit of the first byte with `0x7F`, then take the resulting 31-bit integer modulo 1_000_000.
- Generated codes must always be exactly 6 characters, left-padded with zeros if necessary.

Give me the complete module in a single file.