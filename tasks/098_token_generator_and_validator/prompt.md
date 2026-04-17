Write me an Elixir module called `SecureToken` that generates and validates signed, expiring tokens without any database or persistent state.

I need these two functions in the public API:

- `SecureToken.generate(payload, secret, ttl_seconds)` where `payload` is any Elixir term, `secret` is a binary signing key, and `ttl_seconds` is a positive integer. It must return a URL-safe binary token (no padding issues, safe to embed in URLs or headers) that encodes the payload, the issue timestamp, the expiration timestamp, and an HMAC-SHA256 signature over all of that data.

- `SecureToken.verify(token, secret)` which decodes and validates the token. Return `{:ok, payload}` if the signature is valid and the token has not expired. Return `{:error, :expired}` if the signature is valid but the current time is past the expiration. Return `{:error, :invalid_signature}` if the token structure is readable but the HMAC does not match. Return `{:error, :malformed}` for anything that cannot be decoded at all (truncated input, bad base64, corrupted structure, etc.). The order of checks matters: always verify the signature before checking expiry, so a tampered-and-expired token returns `:invalid_signature`, not `:expired`.

A few implementation requirements:
- Use `:crypto.mac/4` (or `:crypto.hmac/3` on older OTP) with SHA-256 for signing.
- Use `Base.url_encode64/2` with `padding: false` so the output is URL-safe without `=` characters.
- The signed payload should cover all fields (payload bytes + issue time + expiry time) so that none of them can be tampered with independently.
- Use `System.os_time(:second)` for the current wall-clock time.
- Do not use any external dependencies — only the Elixir standard library and OTP.

Give me the complete module in a single file.