defmodule RevocableToken do
  @moduledoc """
  Signed, expiring HMAC-SHA256 tokens with explicit revocation.

  The signing core is stateless: each token carries payload, issue time,
  expiry time, and a unique 16-byte token id (jti), all covered by a MAC.
  A supervised GenServer remembers revoked jtis so an unexpired token can
  be invalidated ahead of its natural expiry.

  ## Wire format

  The decoded binary (before base64) is:

      <<issued_at::signed-64, expires_at::signed-64, jti::binary-16,
        payload_size::unsigned-32, payload::binary, mac::binary-32>>

  ## Clock injection

  `generate/4` and `verify/4` accept an optional `:clock` keyword whose
  value is a zero-arity function returning a Unix epoch second. When
  omitted, `System.os_time(:second)` is used — a test seam only.
  """

  use GenServer

  @hmac_size 32
  @jti_size 16

  @type reason :: :expired | :invalid_signature | :revoked | :malformed

  # --- Client / server lifecycle -----------------------------------------

  @doc """
  Starts the revocation server.

  Accepts a `:name` option under which the server registers; any other
  options are ignored. Returns `{:ok, pid}` on success.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, _opts} = Keyword.pop(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, [], gen_opts)
  end

  @impl true
  def init(_arg), do: {:ok, %{revoked: %{}}}

  @impl true
  def handle_call(request, _from, state) do
    case request do
      {:revoke, jti, expires_at} ->
        {:reply, :ok, %{state | revoked: Map.put(state.revoked, jti, expires_at)}}

      {:revoked?, jti} ->
        reply = if Map.has_key?(state.revoked, jti), do: {:error, :revoked}, else: :ok
        {:reply, reply, state}
    end
  end

  # --- Token generation --------------------------------------------------

  @doc """
  Builds a signed, URL-safe token embedding `payload`, issue/expiry times,
  a fresh random jti, and an HMAC-SHA256 signature over all of it.

  This is stateless and does not touch the revocation server. `ttl_seconds`
  must be a positive integer; `secret` a binary. Supports an optional
  `:clock` in `opts` for deterministic issue/expiry times.
  """
  @spec generate(term(), binary(), pos_integer(), keyword()) :: binary()
  def generate(payload, secret, ttl_seconds, opts \\ [])
      when is_binary(secret) and is_integer(ttl_seconds) and ttl_seconds > 0 do
    issued_at = now(opts)
    expires_at = issued_at + ttl_seconds
    jti = :crypto.strong_rand_bytes(@jti_size)
    payload_bytes = :erlang.term_to_binary(payload)
    payload_size = byte_size(payload_bytes)

    data =
      <<issued_at::signed-64, expires_at::signed-64, jti::binary-size(@jti_size),
        payload_size::unsigned-32, payload_bytes::binary>>

    mac = :crypto.mac(:hmac, :sha256, secret, data)
    Base.url_encode64(<<data::binary, mac::binary>>, padding: false)
  end

  # --- Verification ------------------------------------------------------

  @doc """
  Decodes and validates `token` against `secret` and `server`.

  Returns `{:ok, payload}` when the signature is valid, the token is not
  expired, and its jti has not been revoked. Otherwise returns
  `{:error, :invalid_signature | :expired | :revoked | :malformed}`.

  Checks run in order: base64 decode, MAC split, structural parse, HMAC,
  expiry, revocation, payload deserialization. Any failure before the HMAC
  check yields `:malformed`. Supports an optional `:clock` in `opts`.
  """
  @spec verify(GenServer.server(), binary(), binary(), keyword()) ::
          {:ok, term()} | {:error, reason()}
  def verify(server, token, secret, opts \\ [])

  def verify(server, token, secret, opts) when is_binary(token) and is_binary(secret) do
    with {:ok, decoded} <- decode_base64(token),
         {:ok, data, mac} <- split_mac(decoded),
         {:ok, _issued_at, expires_at, jti, payload_bytes} <- parse_data(data),
         :ok <- verify_mac(secret, data, mac),
         :ok <- check_expiry(expires_at, opts),
         :ok <- check_revoked(server, jti),
         {:ok, payload} <- decode_payload(payload_bytes) do
      {:ok, payload}
    end
  end

  def verify(_server, _token, _secret, _opts), do: {:error, :malformed}

  # --- Revocation --------------------------------------------------------

  @doc """
  Marks `token`'s jti as revoked on `server`.

  The token is parsed structurally to extract its jti; the secret is not
  required and the HMAC is not verified. Returns `:ok`, or
  `{:error, :malformed}` if no jti can be extracted.
  """
  @spec revoke(GenServer.server(), binary()) :: :ok | {:error, :malformed}
  def revoke(server, token) when is_binary(token) do
    case parse_token(token) do
      {:ok, expires_at, jti} -> GenServer.call(server, {:revoke, jti, expires_at})
      :error -> {:error, :malformed}
    end
  end

  def revoke(_server, _token), do: {:error, :malformed}

  # --- Internal helpers --------------------------------------------------

  defp parse_token(token) do
    with {:ok, decoded} <- decode_base64(token),
         {:ok, data, _mac} <- split_mac(decoded),
         {:ok, _issued_at, expires_at, jti, _payload} <- parse_data(data) do
      {:ok, expires_at, jti}
    else
      _ -> :error
    end
  end

  defp check_revoked(server, jti), do: GenServer.call(server, {:revoked?, jti})

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
         <<issued_at::signed-64, expires_at::signed-64, jti::binary-size(@jti_size),
           payload_size::unsigned-32, rest::binary>>
       )
       when byte_size(rest) == payload_size do
    {:ok, issued_at, expires_at, jti, rest}
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
    if now(opts) < expires_at, do: :ok, else: {:error, :expired}
  end

  defp decode_payload(bytes) do
    {:ok, :erlang.binary_to_term(bytes, [:safe])}
  rescue
    ArgumentError -> {:error, :malformed}
  end

  # Constant-time comparison: fold every byte pair into an accumulator with
  # bitwise OR of their XOR, so the whole length is always scanned and there
  # is no early exit on the first differing byte. Mismatched sizes fail up
  # front via the guard.
  defp constant_time_equal?(a, b) when byte_size(a) == byte_size(b) do
    reduce_diff(a, b, 0) === 0
  end

  defp constant_time_equal?(_, _), do: false

  defp reduce_diff(<<x, rest_a::binary>>, <<y, rest_b::binary>>, acc) do
    reduce_diff(rest_a, rest_b, Bitwise.bor(acc, Bitwise.bxor(x, y)))
  end

  defp reduce_diff(<<>>, <<>>, acc), do: acc
end