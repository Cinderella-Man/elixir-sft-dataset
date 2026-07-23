# Implement the missing function

Below you'll find a task's full specification, then a working, tested
solution with one gap: `check_expiry` — every clause body swapped for
`# TODO`. Rebuild exactly that function so the module passes the task's
whole suite again, and leave every other line precisely as shown.

## The task

I'm picking up the token piece of our auth work and I'd rather hand it to you than half-do it myself, so here's what I need.

Write me an Elixir module called `SecureToken` that generates and validates signed, expiring tokens without any database or persistent state. Two functions in the public API, please.

The first is `SecureToken.generate(payload, secret, ttl_seconds, opts \\ [])`, where `payload` is any Elixir term, `secret` is a binary signing key, and `ttl_seconds` is a positive integer. It has to return a URL-safe binary token — no padding issues, safe to drop straight into a URL or a header — that encodes the payload, the issue timestamp, the expiration timestamp, and an HMAC-SHA256 signature over all of that data.

The second is `SecureToken.verify(token, secret, opts \\ [])`, which decodes and validates the token. I want `{:ok, payload}` back when the signature is valid and the token hasn't expired. Give me `{:error, :expired}` when the signature is valid but the current time is at or past the expiration. Give me `{:error, :invalid_signature}` when the token structure parses cleanly but the HMAC doesn't match. And `{:error, :malformed}` for anything that can't be decoded at all — bad base64, too short to contain an HMAC, a header that doesn't match the remaining bytes, non-binary input, that whole category.

Both functions take an optional `opts` keyword list. The only key I want recognized is `:clock`, a zero-arity function returning a Unix epoch second. When it's omitted, read the current time from `System.os_time(:second)`. That option exists purely as a test seam so we can test expiry deterministically — in production the default applies.

I care about the check order inside `verify`, and it's exactly this: base64 decode → split off the trailing 32-byte MAC → structural parse of the header and payload → HMAC verification → expiry check → payload deserialization. Any failure before HMAC verification yields `:malformed`. An HMAC mismatch yields `:invalid_signature`. An expiry failure after the HMAC passes yields `:expired`. A deserialization failure after the HMAC passes yields `:malformed`. One more detail I don't want lost: a token whose `expires_at` equals the current time is already expired, so use a strict `<` on the validity check, not `<=`.

On implementation, a few things are non-negotiable for me. Sign with `:crypto.mac/4` using SHA-256. Encode with `Base.url_encode64/2` and `padding: false`, so the output is URL-safe with no `=` characters. The signed region must cover all the fields — payload bytes plus issue time plus expiry time, plus whatever length prefix you include for framing — so that none of them can be tampered with independently. Compare MACs in constant time; don't short-circuit on the first differing byte. Deserialize the payload with `:erlang.binary_to_term/2` passing the `[:safe]` option. And no external dependencies at all — Elixir standard library and OTP only.

Send it back as the complete module in a single file.

## The module with `check_expiry` missing

```elixir
defmodule SecureToken do
  @moduledoc """
  Stateless, signed, expiring tokens backed by HMAC-SHA256.

  Tokens are self-contained: they carry the payload, issue time, and
  expiry time, all covered by a MAC computed with the caller's secret.
  No database or persistent state is required to verify them.

  ## Wire format

  The decoded binary (before base64) has the layout:

      <<issued_at::signed-64, expires_at::signed-64,
        payload_size::unsigned-32, payload::binary, mac::binary-32>>

  where `payload` is `:erlang.term_to_binary/1` output and `mac` is
  `HMAC-SHA256(secret, issued_at || expires_at || payload_size || payload)`.
  The whole thing is then `Base.url_encode64/2` without padding.

  ## Clock injection

  Both `generate/4` and `verify/3` accept an optional `:clock` keyword
  whose value is a zero-arity function returning a Unix epoch second.
  When omitted, `System.os_time(:second)` is used. This is primarily a
  test seam — in production you should let the default apply.
  """

  import Bitwise

  @hmac_size 32

  @type token :: binary()
  @type reason :: :expired | :invalid_signature | :malformed
  @type opts :: [clock: (-> integer())]

  @doc """
  Generate a signed token for `payload` that expires in `ttl_seconds`.
  """
  @spec generate(term(), binary(), pos_integer(), opts()) :: token()
  def generate(payload, secret, ttl_seconds, opts \\ [])
      when is_binary(secret) and is_integer(ttl_seconds) and ttl_seconds > 0 do
    issued_at = now(opts)
    expires_at = issued_at + ttl_seconds
    payload_bytes = :erlang.term_to_binary(payload)
    payload_size = byte_size(payload_bytes)

    data =
      <<issued_at::signed-64, expires_at::signed-64, payload_size::unsigned-32,
        payload_bytes::binary>>

    mac = :crypto.mac(:hmac, :sha256, secret, data)

    Base.url_encode64(<<data::binary, mac::binary>>, padding: false)
  end

  @doc """
  Verify and decode a token.

  Returns `{:ok, payload}` if the signature is valid and the token has not
  expired. Otherwise returns one of:

    * `{:error, :invalid_signature}` — structure is readable, HMAC doesn't match
    * `{:error, :expired}`           — signature is valid, token is past its expiry
    * `{:error, :malformed}`         — bad base64, too short, corrupted structure, etc.

  The signature is always checked before expiry, so a valid-structure but
  wrong-secret token that also happens to be past its expiry returns
  `:invalid_signature`, never `:expired`.
  """
  @spec verify(token(), binary(), opts()) :: {:ok, term()} | {:error, reason()}
  def verify(token, secret, opts \\ [])

  def verify(token, secret, opts) when is_binary(token) and is_binary(secret) do
    with {:ok, decoded} <- decode_base64(token),
         {:ok, data, mac} <- split_mac(decoded),
         {:ok, _issued_at, expires_at, payload_bytes} <- parse_data(data),
         :ok <- verify_mac(secret, data, mac),
         :ok <- check_expiry(expires_at, opts),
         {:ok, payload} <- decode_payload(payload_bytes) do
      {:ok, payload}
    end
  end

  def verify(_token, _secret, _opts), do: {:error, :malformed}

  # --- internal helpers ---------------------------------------------------

  defp now(opts) do
    case Keyword.get(opts, :clock) do
      nil -> System.os_time(:second)
      fun when is_function(fun, 0) -> fun.()
    end
  end

  defp decode_base64(token) do
    case Base.url_decode64(token, padding: false) do
      {:ok, binary} -> {:ok, binary}
      :error -> {:error, :malformed}
    end
  end

  # Too short to even contain an HMAC → malformed.
  defp split_mac(binary) when byte_size(binary) < @hmac_size do
    {:error, :malformed}
  end

  defp split_mac(binary) do
    data_size = byte_size(binary) - @hmac_size
    <<data::binary-size(^data_size), mac::binary-size(@hmac_size)>> = binary
    {:ok, data, mac}
  end

  # Structural parse runs before MAC verification so that genuinely
  # corrupted bytes (too-short header, payload_size not matching the
  # remaining binary) come back as :malformed rather than being
  # reported as signature failures. An attacker who knows the key can
  # of course still produce a parseable-but-expired token — but that
  # path is governed by verify_mac/check_expiry, not by this function.
  defp parse_data(
         <<issued_at::signed-64, expires_at::signed-64, payload_size::unsigned-32, rest::binary>>
       )
       when byte_size(rest) == payload_size do
    {:ok, issued_at, expires_at, rest}
  end

  defp parse_data(_), do: {:error, :malformed}

  defp verify_mac(secret, data, mac) do
    expected = :crypto.mac(:hmac, :sha256, secret, data)

    if constant_time_equal?(expected, mac) do
      :ok
    else
      {:error, :invalid_signature}
    end
  end

  defp check_expiry(expires_at, opts) do
    # TODO
  end

  # [:safe] prevents decoding of terms that could allocate new atoms or
  # function references — standard hygiene for untrusted binaries even
  # after MAC verification.
  defp decode_payload(bytes) do
    {:ok, :erlang.binary_to_term(bytes, [:safe])}
  rescue
    ArgumentError -> {:error, :malformed}
  end

  # Constant-time equality check over two equal-length binaries. Avoids
  # short-circuiting on the first differing byte, which would otherwise
  # let a careful attacker probe the MAC one byte at a time.
  defp constant_time_equal?(a, b) when byte_size(a) == byte_size(b) do
    a
    |> :binary.bin_to_list()
    |> Enum.zip(:binary.bin_to_list(b))
    |> Enum.reduce(0, fn {x, y}, acc -> bor(acc, bxor(x, y)) end)
    |> Kernel.==(0)
  end

  defp constant_time_equal?(_, _), do: false
end
```

Reply with `check_expiry` alone (bring along any `@doc`/`@spec`/`@impl` lines
that belong directly above it) — just the function, never the whole
module.
