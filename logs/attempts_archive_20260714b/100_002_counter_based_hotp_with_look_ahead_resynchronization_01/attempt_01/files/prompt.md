Write me an Elixir module called `HOTP` that implements RFC 4226 HMAC-Based One-Time Passwords (HOTP) — the *event/counter-based* one-time password scheme — using only the OTP standard library (no external dependencies).

Unlike time-based OTP, HOTP codes are indexed by a monotonically increasing integer counter. The server tracks the next expected counter for each user; because a token can be advanced by the user pressing its button without the server seeing the result, validation uses a **forward-only look-ahead window** and, on success, tells the caller which counter value to store next.

I need these functions in the public API:

- `HOTP.generate_secret()` returns a cryptographically random, base32-encoded secret string (160 bits / 20 bytes of entropy, no padding characters). It must use `:crypto.strong_rand_bytes/1`.

- `HOTP.generate_code(secret, counter)` returns a 6-digit zero-padded string for the given non-negative integer `counter`. It should HMAC-SHA1 the counter (encoded as a big-endian 8-byte unsigned integer) with the base32-decoded secret, apply the RFC 4226 dynamic truncation, and take the result modulo 1_000_000. The generated code must always be exactly 6 characters, left-padded with zeros if necessary. Because the algorithm is fully specified, codes match the canonical RFC 4226 Appendix D test vectors for the secret `"12345678901234567890"` (base32 `GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ`).

- `HOTP.verify(secret, code, counter, opts \\ [])` validates a code (given as a string or an integer; integers are zero-padded to 6 digits) against a forward window of counters. It accepts a `:look_ahead` option (a non-negative integer, default `3`). It checks the counters `counter`, `counter + 1`, …, `counter + look_ahead` **inclusive**, in ascending order. On the first (lowest) matching counter `m` it returns `{:ok, m + 1}` — the next counter the caller should persist. If no counter in the window matches, it returns `:error`. Validation is forward-only: counters below `counter` are never checked.

- `HOTP.provisioning_uri(secret, issuer, account_name, counter)` returns an `otpauth://hotp/` URI (note the `hotp` type) with the label `issuer:account_name` and query parameters `secret`, `issuer`, `algorithm=SHA1`, `digits=6`, and `counter=<counter>` — all properly URI-encoded.

Requirements and constraints:
- Base32 encoding/decoding must follow RFC 4648 (uppercase alphabet A–Z, 2–7). Implement it yourself rather than relying on a library.
- HMAC-SHA1 must be done via Erlang's `:crypto.mac/4`.
- Dynamic truncation (RFC 4226 §5.3): take the last byte of the HMAC, mask with `0x0F` to get the offset, read 4 bytes from that offset, mask the top bit of the first byte with `0x7F`, combine as a 31-bit big-endian integer, then take the result modulo 1_000_000.

Give me the complete module in a single file.