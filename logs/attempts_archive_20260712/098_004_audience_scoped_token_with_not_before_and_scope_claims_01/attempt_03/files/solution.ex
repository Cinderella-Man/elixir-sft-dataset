defmodule ScopedToken do
  @moduledoc """
  Signed, expiring HMAC-SHA256 tokens with audience binding, a not-before
  activation window, and granted scopes.

  Beyond signature and expiry, verification can require an expected
  audience and a set of scopes, and honours a not-before time before which
  the token is not yet valid.

  ## Wire format

  The decoded binary (before base64) is:

      <<issued_at::signed-64, not_before::signed-64, expires_at::signed-64,
        meta_size::unsigned-32, meta::binary,
        payload_size::unsigned-32, payload::binary, mac::binary-32>>

  where `meta` is `:erlang.term_to_binary(%{aud: audience, scopes: scopes})`.
  Everything except the trailing MAC is covered by the MAC.

  ## Clock injection

  `generate/4` and `verify/3` accept an optional `:clock` keyword whose
  value is a zero-arity function returning a Unix epoch second. When
  omitted, `System.os_time(:second)` is used — a test seam only.
  """

  @hmac_size 32

  @type reason ::
          :invalid_signature
          | :not_yet_valid
          | :expired
          | :audience_mismatch
          | :insufficient_scope
          | :malformed

  @doc """
  Generate a URL-safe, signed, expiring token carrying `payload`.

  `secret` is the HMAC key, `ttl_seconds` is a positive integer number of
  seconds until expiry. Recognized `opts`:

    * `:audience` — a binary audience the token is bound to (default `nil`);
    * `:scopes` — a list of binary scopes granted (default `[]`);
    * `:not_before` — non-negative seconds after issue time before which the
      token is not yet valid (default `0`);
    * `:clock` — a zero-arity function returning a Unix epoch second.

  Returns the token as a URL-safe binary produced by
  `Base.url_encode64/2` with `padding: false`.
  """
  @spec generate(term(), binary(), pos_integer(), keyword()) :: binary()
  def generate(payload, secret, ttl_seconds, opts \\ [])
      when is_binary(secret) and is_integer(ttl_seconds) and ttl_seconds > 0 do
    issued_at = now(opts)
    nb_offset = Keyword.get(opts, :not_before, 0)
    not_before = issued_at + nb_offset
    expires_at = issued_at + ttl_seconds
    audience = Keyword.get(opts, :audience)
    scopes = Keyword.get(opts, :scopes, [])

    meta = :erlang.term_to_binary(%{aud: audience, scopes: scopes})
    meta_size = byte_size(meta)
    payload_bytes = :erlang.term_to_binary(payload)
    payload_size = byte_size(payload_bytes)

    data =
      <<issued_at::signed-64, not_before::signed-64, expires_at::signed-64,
        meta_size::unsigned-32, meta::binary, payload_size::unsigned-32,
        payload_bytes::binary>>

    mac = :crypto.mac(:hmac, :sha256, secret, data)
    Base.url_encode64(<<data::binary, mac::binary>>, padding: false)
  end

  @doc """
  Verify `token` against `secret`, returning `{:ok, payload}` when valid.

  Recognized `opts`:

    * `:audience` — expected audience; when non-nil, must equal the token's
      bound audience; when omitted, audience is not checked;
    * `:scopes` — a list of required scopes, all of which must be present in
      the token's granted scopes (default `[]`);
    * `:clock` — a zero-arity function returning a Unix epoch second.

  Checks run in order: base64 decode → split MAC → structural parse → HMAC →
  not-before → expiry → claims decode → audience → scope → payload decode.
  On failure returns `{:error, reason}` where `reason` is one of
  `:malformed`, `:invalid_signature`, `:not_yet_valid`, `:expired`,
  `:audience_mismatch`, or `:insufficient_scope`.
  """
  @spec verify(binary(), binary(), keyword()) :: {:ok, term()} | {:error, reason()}
  def verify(token, secret, opts \\ [])

  def verify(token, secret, opts) when is_binary(token) and is_binary(secret) do
    now_ts = now(opts)

    with {:ok, decoded} <- decode_base64(token),
         {:ok, data, mac} <- split_mac(decoded),
         {:ok, not_before, expires_at, meta_bytes, payload_bytes} <- parse_data(data),
         :ok <- verify_mac(secret, data, mac),
         :ok <- check_not_before(not_before, now_ts),
         :ok <- check_expiry(expires_at, now_ts),
         {:ok, meta} <- decode_meta(meta_bytes),
         :ok <- check_audience(meta, opts),
         :ok <- check_scopes(meta, opts),
         {:ok, payload} <- decode_payload(payload_bytes) do
      {:ok, payload}
    end
  end

  def verify(_token, _secret, _opts), do: {:error, :malformed}

  # --- Internal helpers --------------------------------------------------

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

  defp split_mac(binary) when byte_size(binary) < @hmac_size, do: {:error, :malformed}

  defp split_mac(binary) do
    data_size = byte_size(binary) - @hmac_size
    <<data::binary-size(data_size), mac::binary-size(@hmac_size)>> = binary
    {:ok, data, mac}
  end

  defp parse_data(
         <<_issued_at::signed-64, not_before::signed-64, expires_at::signed-64,
           meta_size::unsigned-32, meta::binary-size(meta_size), payload_size::unsigned-32,
           rest::binary>>
       )
       when byte_size(rest) == payload_size do
    {:ok, not_before, expires_at, meta, rest}
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

  defp check_not_before(not_before, now_ts) do
    if now_ts >= not_before, do: :ok, else: {:error, :not_yet_valid}
  end

  defp check_expiry(expires_at, now_ts) do
    if now_ts < expires_at, do: :ok, else: {:error, :expired}
  end

  defp check_audience(meta, opts) do
    case Keyword.get(opts, :audience) do
      nil ->
        :ok

      expected ->
        if Map.get(meta, :aud) == expected, do: :ok, else: {:error, :audience_mismatch}
    end
  end

  defp check_scopes(meta, opts) do
    required = Keyword.get(opts, :scopes, [])
    granted = Map.get(meta, :scopes, [])

    if Enum.all?(required, &(&1 in granted)) do
      :ok
    else
      {:error, :insufficient_scope}
    end
  end

  defp decode_meta(bytes) do
    case :erlang.binary_to_term(bytes, [:safe]) do
      %{} = meta -> {:ok, meta}
      _ -> {:error, :malformed}
    end
  rescue
    ArgumentError -> {:error, :malformed}
  end

  defp decode_payload(bytes) do
    {:ok, :erlang.binary_to_term(bytes, [:safe])}
  rescue
    ArgumentError -> {:error, :malformed}
  end

  defp constant_time_equal?(a, b) when byte_size(a) == byte_size(b) do
    diff =
      a
      |> :binary.bin_to_list()
      |> Enum.zip(:binary.bin_to_list(b))
      |> Enum.reduce(0, fn {x, y}, acc -> Bitwise.bor(acc, Bitwise.bxor(x, y)) end)

    diff === 0
  end

  defp constant_time_equal?(_, _), do: false
end