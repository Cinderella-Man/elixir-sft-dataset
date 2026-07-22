defmodule CapabilityToken do
  @moduledoc """
  Attenuable capability tokens (macaroon-style).

  A `CapabilityToken` is a self-contained bearer token: it names a capability
  (the *identifier*) and carries an ordered list of *caveats* that narrow the
  authority the token grants. There is no server, no database and no stored
  state — verification is a pure recomputation of an HMAC-SHA256 chain from the
  root key.

  ## The signature chain

      sig_0 = :crypto.mac(:hmac, :sha256, root_key, identifier)
      sig_i = :crypto.mac(:hmac, :sha256, sig_{i-1}, caveat_i)

  Only the final signature `sig_n` travels with the token. Because each caveat
  re-keys the MAC with the previous signature, *anyone* holding a token can
  extend the chain — appending a caveat requires only the signature they already
  have, never the root key. That is what makes `attenuate/2` keyless.

  Going the other way is infeasible: dropping, reordering or editing a caveat
  would require walking the chain backwards to recover an earlier signature,
  which is exactly the preimage the root key protects. So a holder can narrow a
  token offline, but nobody can widen one.

  ## Wire format

  The decoded binary (all integers big-endian, unsigned) is:

      <<1,                              # version byte, always 1
        id_size::16, identifier::binary-size(id_size),
        caveat_count::16,
        # caveat_count repetitions of:
        #   <<len::16, caveat::binary-size(len)>>
        signature::binary-32>>

  which is then `Base.url_encode64/2`-encoded with `padding: false`, so a token
  is URL-safe and contains no `+`, `/` or `=`.

  ## Caveat language

  A caveat is a binary of the form `"key = value"` — the first occurrence of
  `" = "` separates the key from the value (the value may itself contain spaces
  or `=` signs). Exactly three keys are recognized:

    * `"expires_at = <integer>"` — satisfied iff `context[:now]` is an integer
      strictly less than `<integer>`.
    * `"action = <string>"` — satisfied iff `context[:action] == <string>`.
    * `"resource_prefix = <string>"` — satisfied iff `context[:resource]` is a
      binary starting with `<string>`.

  Everything else **fails closed**: an unrecognized key, a caveat with no
  `" = "` separator, a non-integer `expires_at` value, or a context missing the
  key a caveat needs all count as *not satisfied*. An unknown caveat is never
  vacuously true.

  ## Example

      iex> key = "s3cret-root-key"
      iex> token = CapabilityToken.mint(key, "user:42")
      iex> {:ok, token} = CapabilityToken.attenuate(token, "action = read")
      iex> CapabilityToken.authorize(token, key, %{action: "read"})
      :ok
      iex> CapabilityToken.authorize(token, key, %{action: "write"})
      {:error, {:caveat_failed, "action = read"}}
  """

  @version 1
  @signature_size 32
  @max_caveat_size 65_535
  @separator " = "

  @typedoc "A URL-safe, base64url-encoded capability token."
  @type token :: binary()

  @typedoc "The request being authorized."
  @type context :: %{optional(atom()) => term()}

  @typedoc "Why authorization failed."
  @type reason :: :malformed | :invalid_signature | {:caveat_failed, binary()}

  @doc """
  Mints a fresh token with zero caveats.

  `root_key` is the binary HMAC signing key and `identifier` is a binary naming
  the capability (for example `"user:42"`). The returned token is a URL-safe
  binary carrying `sig_0 = HMAC-SHA256(root_key, identifier)`.

      iex> token = CapabilityToken.mint("k", "user:42")
      iex> CapabilityToken.inspect_token(token)
      {:ok, %{identifier: "user:42", caveats: []}}
  """
  @spec mint(binary(), binary()) :: token()
  def mint(root_key, identifier) when is_binary(root_key) and is_binary(identifier) do
    encode(identifier, [], mac(root_key, identifier))
  end

  @doc """
  Appends one caveat to `token`, narrowing it — no root key required.

  `caveat` must be a non-empty binary of at most #{@max_caveat_size} bytes. The
  returned token carries the original caveats, in order, followed by the new
  one, and a signature extended by one link of the chain. Tokens are immutable
  binaries, so the original `token` is untouched.

  Returns `{:error, :malformed}` if `token` is not a decodable token, if either
  argument is not a binary, or if `caveat` is empty or oversized.

      iex> token = CapabilityToken.mint("k", "user:42")
      iex> {:ok, narrowed} = CapabilityToken.attenuate(token, "action = read")
      iex> CapabilityToken.inspect_token(narrowed)
      {:ok, %{identifier: "user:42", caveats: ["action = read"]}}
  """
  @spec attenuate(token(), binary()) :: {:ok, token()} | {:error, :malformed}
  def attenuate(token, caveat) when is_binary(token) and is_binary(caveat) do
    with true <- byte_size(caveat) in 1..@max_caveat_size,
         {:ok, identifier, caveats, signature} <- decode(token) do
      {:ok, encode(identifier, caveats ++ [caveat], mac(signature, caveat))}
    else
      _ -> {:error, :malformed}
    end
  end

  def attenuate(_token, _caveat), do: {:error, :malformed}

  @doc """
  Decodes a token without any key and without checking its signature.

  Returns `{:ok, %{identifier: identifier, caveats: caveats}}` with the caveats
  in the order they were attached, or `{:error, :malformed}` if the token cannot
  be decoded (including for non-binary input).

  This is a debugging/introspection helper: it makes **no authenticity claim
  whatsoever**. Use `authorize/3` to decide anything that matters.

      iex> {:ok, token} = CapabilityToken.attenuate(CapabilityToken.mint("k", "a"), "action = read")
      iex> CapabilityToken.inspect_token(token)
      {:ok, %{identifier: "a", caveats: ["action = read"]}}
  """
  @spec inspect_token(token()) ::
          {:ok, %{identifier: binary(), caveats: [binary()]}} | {:error, :malformed}
  def inspect_token(token) when is_binary(token) do
    case decode(token) do
      {:ok, identifier, caveats, _signature} ->
        {:ok, %{identifier: identifier, caveats: caveats}}

      :error ->
        {:error, :malformed}
    end
  end

  def inspect_token(_token), do: {:error, :malformed}

  @doc """
  Authorizes `token` under `root_key` for the request described by `context`.

  Returns `:ok` when the signature chain recomputes to the signature the token
  carries **and** every caveat is satisfied by `context`. Checks run in exactly
  this order:

    1. decode and structural parse — failure (or a non-binary token, non-binary
       root key, or non-map context) yields `{:error, :malformed}`;
    2. signature chain verification, compared in constant time — a mismatch
       yields `{:error, :invalid_signature}`;
    3. caveats, in attachment order — the first unsatisfied caveat yields
       `{:error, {:caveat_failed, caveat}}` and later caveats are not evaluated.

  Because signature verification always precedes caveat evaluation, a token that
  is both expired and signed with the wrong key reports `:invalid_signature`.

      iex> token = CapabilityToken.mint("k", "user:42")
      iex> {:ok, token} = CapabilityToken.attenuate(token, "expires_at = 100")
      iex> CapabilityToken.authorize(token, "k", %{now: 99})
      :ok
      iex> CapabilityToken.authorize(token, "k", %{now: 100})
      {:error, {:caveat_failed, "expires_at = 100"}}
      iex> CapabilityToken.authorize(token, "wrong", %{now: 99})
      {:error, :invalid_signature}
  """
  @spec authorize(token(), binary(), context()) :: :ok | {:error, reason()}
  def authorize(token, root_key, context)
      when is_binary(token) and is_binary(root_key) and is_map(context) do
    with {:ok, identifier, caveats, signature} <- decode(token),
         true <- secure_compare(chain(root_key, identifier, caveats), signature) do
      check_caveats(caveats, context)
    else
      :error -> {:error, :malformed}
      false -> {:error, :invalid_signature}
    end
  end

  def authorize(_token, _root_key, _context), do: {:error, :malformed}

  ## Encoding / decoding

  @spec encode(binary(), [binary()], binary()) :: token()
  defp encode(identifier, caveats, signature) do
    payload =
      for caveat <- caveats, into: <<>>, do: <<byte_size(caveat)::16, caveat::binary>>

    binary =
      <<@version, byte_size(identifier)::16, identifier::binary, length(caveats)::16,
        payload::binary, signature::binary-size(@signature_size)>>

    Base.url_encode64(binary, padding: false)
  end

  @spec decode(binary()) :: {:ok, binary(), [binary()], binary()} | :error
  defp decode(token) do
    with {:ok, binary} <- Base.url_decode64(token, padding: false),
         <<@version, id_size::16, identifier::binary-size(id_size), count::16, rest::binary>> <-
           binary,
         {:ok, caveats, <<signature::binary-size(@signature_size)>>} <-
           take_caveats(rest, count, []) do
      {:ok, identifier, caveats, signature}
    else
      _ -> :error
    end
  end

  @spec take_caveats(binary(), non_neg_integer(), [binary()]) ::
          {:ok, [binary()], binary()} | :error
  defp take_caveats(rest, 0, acc), do: {:ok, Enum.reverse(acc), rest}

  defp take_caveats(<<len::16, caveat::binary-size(len), rest::binary>>, count, acc)
       when count > 0 do
    take_caveats(rest, count - 1, [caveat | acc])
  end

  defp take_caveats(_rest, _count, _acc), do: :error

  ## Signature chain

  @spec chain(binary(), binary(), [binary()]) :: binary()
  defp chain(root_key, identifier, caveats) do
    Enum.reduce(caveats, mac(root_key, identifier), fn caveat, sig -> mac(sig, caveat) end)
  end

  @spec mac(binary(), binary()) :: binary()
  defp mac(key, data), do: :crypto.mac(:hmac, :sha256, key, data)

  @spec secure_compare(binary(), binary()) :: boolean()
  defp secure_compare(left, right) when byte_size(left) == byte_size(right) do
    xor_diff(left, right, 0) == 0
  end

  defp secure_compare(_left, _right), do: false

  @spec xor_diff(binary(), binary(), non_neg_integer()) :: non_neg_integer()
  defp xor_diff(<<a, left::binary>>, <<b, right::binary>>, acc) do
    xor_diff(left, right, Bitwise.bor(acc, Bitwise.bxor(a, b)))
  end

  defp xor_diff(<<>>, <<>>, acc), do: acc

  ## Caveat evaluation

  @spec check_caveats([binary()], context()) :: :ok | {:error, {:caveat_failed, binary()}}
  defp check_caveats([], _context), do: :ok

  defp check_caveats([caveat | rest], context) do
    if satisfied?(caveat, context) do
      check_caveats(rest, context)
    else
      {:error, {:caveat_failed, caveat}}
    end
  end

  @spec satisfied?(binary(), context()) :: boolean()
  defp satisfied?(caveat, context) do
    case :binary.split(caveat, @separator) do
      [key, value] -> check(key, value, context)
      _ -> false
    end
  end

  @spec check(binary(), binary(), context()) :: boolean()
  defp check("expires_at", value, context) do
    case {parse_integer(value), Map.get(context, :now)} do
      {{:ok, deadline}, now} when is_integer(now) -> now < deadline
      _ -> false
    end
  end

  defp check("action", value, context), do: Map.get(context, :action) === value

  defp check("resource_prefix", value, context) do
    resource = Map.get(context, :resource)
    is_binary(resource) and String.starts_with?(resource, value)
  end

  defp check(_key, _value, _context), do: false

  @spec parse_integer(binary()) :: {:ok, integer()} | :error
  defp parse_integer(value) do
    case Integer.parse(value) do
      {integer, ""} -> {:ok, integer}
      _ -> :error
    end
  end
end