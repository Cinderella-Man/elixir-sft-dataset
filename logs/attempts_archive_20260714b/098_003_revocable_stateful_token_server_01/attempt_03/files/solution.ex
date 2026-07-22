defmodule RevocableToken do
  @moduledoc """
  Issues and validates signed, expiring tokens that additionally support
  **revocation**.

  Unlike a purely stateless token, a `RevocableToken` server owns the signing
  secret and maintains an in-memory set of revoked tokens. Once a token has been
  revoked on a server it fails validation on that server even though its HMAC
  signature is still cryptographically valid and it has not yet expired.

  Each token is a URL-safe base64 string (no padding) whose decoded bytes are:

      <<id::binary-size(16), issued_at::signed-64, expires_at::signed-64,
        payload_len::32, payload::binary-size(payload_len)>> <> mac

  where `mac` is a 32-byte `HMAC-SHA256` over everything that precedes it. Every
  field — including the random per-token id and the length prefix used for
  framing — lies inside the signed region, so none of them can be tampered with
  independently.

  Validation inside `verify/2` proceeds in exactly this order:

    1. base64 decode
    2. split off the trailing 32-byte MAC
    3. structural parse of the header and payload
    4. HMAC verification
    5. revocation check
    6. expiry check
    7. payload deserialization

  Any failure before HMAC verification yields `:malformed`; an HMAC mismatch
  yields `:invalid_signature`; a revoked token yields `:revoked`; an expired
  token yields `:expired`; and a post-HMAC deserialization failure yields
  `:malformed`.
  """

  use GenServer

  @id_bytes 16
  @mac_bytes 32

  @typedoc "A validation failure reason returned by `verify/2`."
  @type error :: :expired | :invalid_signature | :revoked | :malformed

  # ----------------------------------------------------------------------------
  # Public API
  # ----------------------------------------------------------------------------

  @doc """
  Starts a `RevocableToken` server.

  `opts` is a keyword list. The `:secret` key (a binary signing key) is
  required. The optional `:clock` key is a zero-arity function returning a Unix
  epoch second; when omitted the server reads `System.os_time(:second)`. The
  optional `:name` key registers the server under a name.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {name, init_opts} = Keyword.pop(opts, :name)
    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, init_opts, server_opts)
  end

  @doc """
  Issues a fresh token on `server`.

  `payload` may be any Elixir term and `ttl_seconds` is a positive integer. The
  returned token is a URL-safe binary carrying the payload, the issue and
  expiration timestamps, a server-generated random id, and an `HMAC-SHA256`
  signature over all of that data. Because each token carries a fresh random id,
  issuing the same payload twice produces two different tokens.
  """
  @spec issue(GenServer.server(), term(), pos_integer()) :: {:ok, binary()}
  def issue(server, payload, ttl_seconds)
      when is_integer(ttl_seconds) and ttl_seconds > 0 do
    GenServer.call(server, {:issue, payload, ttl_seconds})
  end

  @doc """
  Decodes and validates `token` against `server`.

  Returns `{:ok, payload}` when the signature is valid, the token is not revoked
  and it has not expired. Otherwise returns `{:error, reason}` with `reason` one
  of `:expired`, `:invalid_signature`, `:revoked` or `:malformed`. Verifying a
  token any number of times does not change its status. Non-binary input yields
  `{:error, :malformed}`.
  """
  @spec verify(GenServer.server(), term()) :: {:ok, term()} | {:error, error()}
  def verify(server, token) do
    GenServer.call(server, {:verify, token})
  end

  @doc """
  Marks `token` as revoked on `server` and returns `:ok`.

  Revocation is per-token (revoking one token does not affect any other) and
  per-server (revoking a token on one server does not revoke it on another).
  """
  @spec revoke(GenServer.server(), term()) :: :ok
  def revoke(server, token) do
    GenServer.call(server, {:revoke, token})
  end

  # ----------------------------------------------------------------------------
  # GenServer callbacks
  # ----------------------------------------------------------------------------

  @impl true
  def init(opts) do
    secret = Keyword.fetch!(opts, :secret)
    clock = Keyword.get(opts, :clock, fn -> System.os_time(:second) end)
    {:ok, %{secret: secret, clock: clock, revoked: MapSet.new()}}
  end

  @impl true
  def handle_call({:issue, payload, ttl}, _from, state) do
    now = state.clock.()
    expires_at = now + ttl
    id = :crypto.strong_rand_bytes(@id_bytes)
    payload_bin = :erlang.term_to_binary(payload)

    signed =
      <<id::binary-size(@id_bytes), now::signed-64, expires_at::signed-64,
        byte_size(payload_bin)::32, payload_bin::binary>>

    mac = :crypto.mac(:hmac, :sha256, state.secret, signed)
    token = Base.url_encode64(signed <> mac, padding: false)
    {:reply, {:ok, token}, state}
  end

  def handle_call({:verify, token}, _from, state) do
    {:reply, do_verify(token, state), state}
  end

  def handle_call({:revoke, token}, _from, state) do
    case token_id(token) do
      {:ok, id} ->
        {:reply, :ok, %{state | revoked: MapSet.put(state.revoked, id)}}

      {:error, _reason} ->
        {:reply, :ok, state}
    end
  end

  # ----------------------------------------------------------------------------
  # Internal helpers
  # ----------------------------------------------------------------------------

  @spec do_verify(term(), map()) :: {:ok, term()} | {:error, error()}
  defp do_verify(token, state) do
    with {:ok, bin} <- decode(token),
         {:ok, signed, mac} <- split_mac(bin),
         {:ok, id, expires_at, payload_bin} <- parse(signed),
         :ok <- check_mac(signed, mac, state.secret),
         :ok <- check_revoked(id, state.revoked),
         :ok <- check_expiry(expires_at, state.clock),
         {:ok, payload} <- deserialize(payload_bin) do
      {:ok, payload}
    end
  end

  @spec token_id(term()) :: {:ok, binary()} | {:error, :malformed}
  defp token_id(token) do
    with {:ok, bin} <- decode(token),
         {:ok, signed, _mac} <- split_mac(bin),
         {:ok, id, _expires_at, _payload_bin} <- parse(signed) do
      {:ok, id}
    end
  end

  @spec decode(term()) :: {:ok, binary()} | {:error, :malformed}
  defp decode(token) when is_binary(token) do
    case Base.url_decode64(token, padding: false) do
      {:ok, bin} -> {:ok, bin}
      :error -> {:error, :malformed}
    end
  end

  defp decode(_token), do: {:error, :malformed}

  @spec split_mac(binary()) ::
          {:ok, binary(), binary()} | {:error, :malformed}
  defp split_mac(bin) when byte_size(bin) >= @mac_bytes do
    size = byte_size(bin) - @mac_bytes
    <<signed::binary-size(size), mac::binary-size(@mac_bytes)>> = bin
    {:ok, signed, mac}
  end

  defp split_mac(_bin), do: {:error, :malformed}

  @spec parse(binary()) ::
          {:ok, binary(), integer(), binary()} | {:error, :malformed}
  defp parse(signed) do
    case signed do
      <<id::binary-size(@id_bytes), _issued_at::signed-64, expires_at::signed-64, len::32,
        payload::binary-size(len)>> ->
        {:ok, id, expires_at, payload}

      _other ->
        {:error, :malformed}
    end
  end

  @spec check_mac(binary(), binary(), binary()) ::
          :ok | {:error, :invalid_signature}
  defp check_mac(signed, mac, secret) do
    expected = :crypto.mac(:hmac, :sha256, secret, signed)
    if secure_compare(expected, mac), do: :ok, else: {:error, :invalid_signature}
  end

  @spec check_revoked(binary(), MapSet.t()) :: :ok | {:error, :revoked}
  defp check_revoked(id, revoked) do
    if MapSet.member?(revoked, id), do: {:error, :revoked}, else: :ok
  end

  @spec check_expiry(integer(), (-> integer())) :: :ok | {:error, :expired}
  defp check_expiry(expires_at, clock) do
    if clock.() < expires_at, do: :ok, else: {:error, :expired}
  end

  @spec deserialize(binary()) :: {:ok, term()} | {:error, :malformed}
  defp deserialize(bin) do
    {:ok, :erlang.binary_to_term(bin, [:safe])}
  rescue
    ArgumentError -> {:error, :malformed}
  end

  # Constant-time equality: never short-circuits on the first differing byte.
  @spec secure_compare(binary(), binary()) :: boolean()
  defp secure_compare(left, right)
       when is_binary(left) and is_binary(right) and
              byte_size(left) == byte_size(right) do
    secure_compare(left, right, 0) === 0
  end

  defp secure_compare(_left, _right), do: false

  @spec secure_compare(binary(), binary(), non_neg_integer()) :: non_neg_integer()
  defp secure_compare(<<x, left::binary>>, <<y, right::binary>>, acc) do
    secure_compare(left, right, Bitwise.bor(acc, Bitwise.bxor(x, y)))
  end

  defp secure_compare(<<>>, <<>>, acc), do: acc
end
