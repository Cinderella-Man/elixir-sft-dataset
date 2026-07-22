Write me an Elixir module called `CapabilityToken` that implements
**attenuable capability tokens** (macaroon-style) — bearer tokens that
anyone holding them can *narrow* offline, without the signing key, but
that nobody can *widen*.

There is no server, no database, and no stored state: a token is a
self-contained binary, and verification is a pure recomputation from the
root key.

## Public API

- `CapabilityToken.mint(root_key, identifier)` — `root_key` is a binary
  signing key, `identifier` is a binary naming the capability (e.g.
  `"user:42"`). Returns a URL-safe binary token with zero caveats.

- `CapabilityToken.attenuate(token, caveat)` — appends one caveat to a
  token **without needing the root key**. `caveat` is a non-empty binary
  (1..65_535 bytes). Returns `{:ok, new_token}`. Returns
  `{:error, :malformed}` if `token` is not a decodable token, if `token`
  or `caveat` is not a binary, or if `caveat` is empty or longer than
  65_535 bytes. The original token is unchanged (tokens are immutable
  binaries); the new token carries the old caveats in order, followed by
  the new one.

- `CapabilityToken.inspect_token(token)` — decodes a token **without any
  key and without checking the signature**. Returns
  `{:ok, %{identifier: identifier, caveats: caveats}}` where `caveats` is
  the list of caveat binaries in the order they were attached, or
  `{:error, :malformed}` if the token cannot be decoded (including for
  non-binary input). This is a debugging/introspection helper — it makes
  no authenticity claim whatsoever.

- `CapabilityToken.authorize(token, root_key, context)` — the real check.
  `context` is a map describing the request being authorized. Returns
  `:ok` if the token's signature chain verifies under `root_key` **and**
  every caveat is satisfied by `context`. Otherwise returns
  `{:error, reason}` (see below).

## Wire format

Build the decoded binary exactly like this (all integers big-endian,
unsigned), then `Base.url_encode64/2` it with `padding: false` so the
token is URL-safe and contains no `+`, `/`, or `=`:

    <<1,                              # version byte, always 1
      id_size::16, identifier::binary-size(id_size),
      caveat_count::16,
      # caveat_count repetitions of:
      #   <<len::16, caveat::binary-size(len)>>
      signature::binary-32>>

So the signature is always the trailing 32 bytes of the decoded binary.

## Signature chain

The signature is an HMAC-SHA256 chain in which each caveat re-keys the
MAC with the previous signature:

    sig_0 = :crypto.mac(:hmac, :sha256, root_key, identifier)
    sig_i = :crypto.mac(:hmac, :sha256, sig_{i-1}, caveat_i)

The token carries only the final signature `sig_n`. This is what makes
attenuation keyless (you can extend the chain from the signature you
hold) while forgery stays impossible (you cannot walk the chain
backwards to drop, reorder, or edit a caveat — doing so requires the
root key). `authorize/3` recomputes the whole chain from `root_key` and
the token's own identifier + caveats and compares the result to the
carried signature **in constant time** (no short-circuit on the first
differing byte).

## Caveat language

A caveat is a binary of the form `"key = value"` — a key, then a space,
an equals sign, and a space, then the value (the value may itself
contain spaces or `=`; only the first `" = "` separates). Exactly three
keys are recognized:

- `"expires_at = <integer>"` — satisfied iff `context[:now]` is an
  integer and `context[:now] < <integer>`. Strictly less: at exactly the
  expiry second the caveat is **not** satisfied. The value must parse as
  a complete integer (leading `-` allowed, trailing garbage not).
- `"action = <string>"` — satisfied iff `context[:action]` is exactly
  equal to `<string>` (binary equality).
- `"resource_prefix = <string>"` — satisfied iff `context[:resource]` is
  a binary that starts with `<string>`.

Everything else **fails closed**: an unrecognized key, a caveat with no
`" = "` separator, a non-integer `expires_at` value, or a context that
is missing the key a caveat needs — all count as *not satisfied*. Never
treat an unknown caveat as vacuously true.

## Check order and error values inside `authorize/3`

Exactly this order:

1. base64 decode → structural parse (version byte, sizes, caveat count,
   exactly 32 trailing signature bytes). Any failure here, or a
   non-binary token / non-binary root key / non-map context, yields
   `{:error, :malformed}`.
2. signature chain verification → mismatch yields
   `{:error, :invalid_signature}`.
3. caveats, evaluated in attachment order → the **first** unsatisfied
   caveat yields `{:error, {:caveat_failed, caveat}}`, where `caveat` is
   that caveat's exact binary. Later caveats are not evaluated.

Signature verification always precedes caveat evaluation, so a token
that is both expired and signed with the wrong key reports
`:invalid_signature`, never `{:caveat_failed, _}`.

## Implementation requirements

- `:crypto.mac/4` with SHA-256 for every link of the chain.
- `Base.url_encode64/2` / `Base.url_decode64/2` with `padding: false`.
- Constant-time signature comparison.
- No external dependencies — Elixir standard library and OTP only.
- No process state, no ETS, no files.

Give me the complete module in a single file.