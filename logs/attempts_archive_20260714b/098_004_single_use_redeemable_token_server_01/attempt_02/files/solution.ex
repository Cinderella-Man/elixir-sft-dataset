defmodule SingleUseToken do
  @moduledoc """
  Issues signed, expiring, single-use tokens and redeems them exactly once.

  Signing is stateless HMAC-SHA256 over the token's fields (a fresh per-token
  unique id, the issue and expiration timestamps, and the payload). On top of
  the stateless signature, a `GenServer` keeps an in-memory, per-server ledger
  of the unique ids it has already redeemed, so a replayed token is rejected
  with `{:error, :already_redeemed}`.

  A token is a `Base.url_encode64/2` (no padding) encoding of a signed region
  concatenated with its 32-byte MAC. The signed region carries length-prefixed
  fields so no field can be tampered with independently without invalidating
  the signature.

  Redemption runs entirely inside the server process, so concurrent redemptions
  of the same token are serialized and cannot both succeed.

  ## Check order in `redeem/2`

  base64 decode -> split trailing 32-byte MAC -> structural parse -> HMAC
  verification -> expiry check -> single-use check -> payload deserialization.

  Any structural failure before HMAC verification yields `:malformed`. An HMAC
  mismatch yields `:invalid_signature`. Expiry (with strict `<`) yields
  `:expired`. A replay yields `:already_redeemed`. The ledger is updated only on
  a fully successful redemption.
  """

  use GenServer

  @mac_size 32
  @id_size 16

  @typedoc "A running server: a pid or a registered name."
  @type server :: GenServer.server()

  @typedoc "An opaque, URL-safe, signed single-use token."
  @type token :: binary()

  @typedoc "Reasons a redemption can fail."
  @type reason :: :malformed | :invalid_signature | :expired | :already_redeemed

  @doc """
  Starts a token server.

  `opts` must contain `:secret` (a binary HMAC key). It may contain `:clock`
  (a zero-arity function returning a Unix epoch second, used as a test seam for
  deterministic expiry) and `:name` (a registration name). When `:clock` is
  omitted, the server reads time from `System.os_time(:second)`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    {name, init_opts} = Keyword.pop(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, init_opts, gen_opts)
  end

  @doc """
  Issues a fresh single-use token for `payload` valid for `ttl_seconds`.

  `payload` may be any Elixir term. `ttl_seconds` must be a positive integer.
  Every call embeds a fresh unique id, so issuing the same payload twice yields
  two different tokens. Returns `{:ok, token}`.
  """
  @spec issue(server(), term(), pos_integer()) :: {:ok, token()}
  def issue(server, payload, ttl_seconds)
      when is_integer(ttl_seconds) and ttl_seconds > 0 do
    GenServer.call(server, {:issue, payload, ttl_seconds})
  end

  @doc """
  Validates and consumes `token`, returning `{:ok, payload}` on first success.

  Returns `{:error, :already_redeemed}` if this exact token was already redeemed
  on this server, `{:error, :expired}` if the signature is valid but the token
  has expired, `{:error, :invalid_signature}` if the structure parses but the
  HMAC does not match this server's secret, and `{:error, :malformed}` for
  anything that cannot be decoded at all.
  """
  @spec redeem(server(), term()) :: {:ok, term()} | {:error, reason()}
  def redeem(server, token) do
    GenServer.call(server, {:redeem, token})
  end

  @impl true
  @spec init(term()) :: {:ok, map()}
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.os_time(:second) end)

    case Keyword.fetch!(opts, :secret) do
      secret when is_binary(secret) ->
        {:ok, %{secret: secret, clock: clock, redeemed: MapSet.new()}}

      _other ->
        raise ArgumentError, "expected :secret to be a binary HMAC key"
    end
  end

  @impl true
  def handle_call({:issue, payload, ttl}, _from, state) do
    {:reply, {:ok, build_token(payload, ttl, state)}, state}
  end

  def handle_call({:redeem, token}, _from, state) do
    case do_redeem(token, state) do
      {:ok, payload, id} ->
        {:reply, {:ok, payload}, %{state | redeemed: MapSet.put(state.redeemed, id)}}

      {:error, _reason} = error ->
        {:reply, error, state}
    end
  end

  # --- Issuing --------------------------------------------------------------

  @spec build_token(term(), pos_integer(), map()) :: token()
  defp build_token(payload, ttl, %{secret: secret, clock: clock}) do
    now = clock.()
    id = :crypto.strong_rand_bytes(@id_size)
    payload_bin = :erlang.term_to_binary(payload)
    region = encode_region(id, now, now + ttl, payload_bin)
    mac = :crypto.mac(:hmac, :sha256, secret, region)
    Base.url_encode64(region <> mac, padding: false)
  end

  @spec encode_region(binary(), integer(), integer(), binary()) :: binary()
  defp encode_region(id, issued_at, expires_at, payload_bin) do
    <<byte_size(id)::16, id::binary, issued_at::64, expires_at::64, byte_size(payload_bin)::32,
      payload_bin::binary>>
  end

  # --- Redemption pipeline --------------------------------------------------

  @spec do_redeem(term(), map()) ::
          {:ok, term(), binary()} | {:error, reason()}
  defp do_redeem(token, %{secret: secret, clock: clock, redeemed: redeemed}) do
    with {:ok, bin} <- base64_decode(token),
         {:ok, region, mac} <- split_mac(bin),
         {:ok, id, _issued_at, expires_at, payload_bin} <- parse_region(region),
         :ok <- verify_mac(region, mac, secret),
         :ok <- check_expiry(expires_at, clock.()),
         :ok <- check_unused(id, redeemed),
         {:ok, payload} <- deserialize(payload_bin) do
      {:ok, payload, id}
    end
  end

  @spec base64_decode(term()) :: {:ok, binary()} | {:error, :malformed}
  defp base64_decode(token) when is_binary(token) do
    case Base.url_decode64(token, padding: false) do
      {:ok, bin} -> {:ok, bin}
      :error -> {:error, :malformed}
    end
  end

  defp base64_decode(_token), do: {:error, :malformed}

  @spec split_mac(binary()) :: {:ok, binary(), binary()} | {:error, :malformed}
  defp split_mac(bin) do
    size = byte_size(bin)

    if size < @mac_size do
      {:error, :malformed}
    else
      region = binary_part(bin, 0, size - @mac_size)
      mac = binary_part(bin, size - @mac_size, @mac_size)
      {:ok, region, mac}
    end
  end

  @spec parse_region(binary()) ::
          {:ok, binary(), integer(), integer(), binary()} | {:error, :malformed}
  defp parse_region(<<id_len::16, rest::binary>>) do
    case rest do
      <<id::binary-size(id_len), issued_at::64, expires_at::64, plen::32,
        payload_bin::binary-size(plen)>> ->
        {:ok, id, issued_at, expires_at, payload_bin}

      _ ->
        {:error, :malformed}
    end
  end

  defp parse_region(_region), do: {:error, :malformed}

  @spec verify_mac(binary(), binary(), binary()) ::
          :ok | {:error, :invalid_signature}
  defp verify_mac(region, mac, secret) do
    expected = :crypto.mac(:hmac, :sha256, secret, region)

    if secure_compare(mac, expected) do
      :ok
    else
      {:error, :invalid_signature}
    end
  end

  @spec check_expiry(integer(), integer()) :: :ok | {:error, :expired}
  defp check_expiry(expires_at, now) do
    if now < expires_at, do: :ok, else: {:error, :expired}
  end

  @spec check_unused(binary(), MapSet.t()) :: :ok | {:error, :already_redeemed}
  defp check_unused(id, redeemed) do
    if MapSet.member?(redeemed, id), do: {:error, :already_redeemed}, else: :ok
  end

  @spec deserialize(binary()) :: {:ok, term()} | {:error, :malformed}
  defp deserialize(payload_bin) do
    {:ok, :erlang.binary_to_term(payload_bin, [:safe])}
  rescue
    ArgumentError -> {:error, :malformed}
  end

  # --- Constant-time comparison ---------------------------------------------

  @spec secure_compare(binary(), binary()) :: boolean()
  defp secure_compare(left, right) do
    byte_size(left) == byte_size(right) and secure_compare(left, right, 0)
  end

  @spec secure_compare(binary(), binary(), non_neg_integer()) :: boolean()
  defp secure_compare(<<>>, <<>>, acc), do: acc === 0

  defp secure_compare(<<x, left::binary>>, <<y, right::binary>>, acc) do
    secure_compare(left, right, :erlang.bor(acc, :erlang.bxor(x, y)))
  end
end
