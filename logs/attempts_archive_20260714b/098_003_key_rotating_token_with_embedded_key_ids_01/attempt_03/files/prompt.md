Write me an Elixir module called `RotatingToken` that generates and validates
signed, expiring HMAC-SHA256 tokens with support for **signing-key rotation via
embedded key IDs**. Instead of a single secret shared by generation and
verification, each token names the key that signed it, and verification looks the
key up in a keyring so old keys can be retired gracefully.

Public API:

- `RotatingToken.generate(payload, secret, kid, ttl_seconds, opts \\ [])` where
  `payload` is any Elixir term, `secret` is the binary signing key, `kid` is a
  binary key id (at most 255 bytes), and `ttl_seconds` is a positive integer. It
  returns a URL-safe binary token (via `Base.url_encode64/2` with
  `padding: false`) encoding the payload, issue timestamp, expiration timestamp,
  the `kid`, and an HMAC-SHA256 signature over all of that data (including the
  `kid`).

- `RotatingToken.verify(token, keyring, opts \\ [])` where `keyring` is a map of
  `%{kid => secret}`. It decodes the token, reads the embedded `kid`, and looks up
  the corresponding secret. Return `{:ok, payload}` if the key is known, the
  signature is valid, and the token has not expired. Return
  `{:error, :unknown_key}` if the token parses cleanly but its `kid` is not in the
  keyring. Return `{:error, :invalid_signature}` if the key is known but the HMAC
  does not match. Return `{:error, :expired}` if the signature is valid but the
  current time is at or past expiration. Return `{:error, :malformed}` for
  anything that cannot be decoded at all (bad base64, too short to contain the
  HMAC, a header that doesn't match the remaining bytes, non-binary/non-map input,
  post-HMAC deserialization failure).

The exact check order inside `verify` is: base64 decode → split off the trailing
32-byte MAC → structural parse (including reading the `kid`) → key lookup by
`kid` → HMAC verification → expiry check → payload deserialization. Any failure
before key lookup yields `:malformed`. An unknown `kid` yields `:unknown_key`
(checked before the HMAC, since without the key there is nothing to verify
against). A known key with a mismatched MAC yields `:invalid_signature`. A valid
signature past expiry yields `:expired`. A token whose `expires_at` equals the
current time is already expired (strict `<` on the validity check).

Both functions take an optional `:clock` in `opts`, a zero-arity function
returning a Unix epoch second; when omitted, `System.os_time(:second)` is used —
a test seam only.

Implementation requirements:

- Use `:crypto.mac/4` with SHA-256 for signing.
- Frame the `kid` with a one-byte length prefix so it can be read back
  unambiguously, and include the whole framed region under the MAC.
- Compare MACs in constant time (no early exit on first differing byte).
- Deserialize the payload with `:erlang.binary_to_term/2` using `[:safe]`.
- No external dependencies — only the Elixir standard library and OTP.

Give me the complete module in a single file.