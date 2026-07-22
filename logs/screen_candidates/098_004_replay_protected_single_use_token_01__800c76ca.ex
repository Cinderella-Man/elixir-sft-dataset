defmodule SingleUseToken do
  @moduledoc """
  A GenServer that issues and redeems signed, expiring, single-use tokens.

  A token is a URL-safe base64 string wrapping a binary frame:

      nonce (16 bytes) ||
      issued_at (64-bit big-endian signed) ||
      expires_at (64-bit big-endian signed) ||
      payload_size (32-bit big-endian unsigned) ||
      payload (`:erlang.term_to_binary/1` bytes) ||
      mac (32 bytes, HMAC-SHA256 over everything before it)

  The HMAC covers every field — including the payload length prefix used for
  framing — so no field can be tampered with independently.

  Unlike a purely stateless token, redemption *consumes* the token: the server
  keeps the set of consumed nonces in memory and rejects any replay. All
  redemption runs through the single GenServer process, which serializes the
  read-then-consume sequence.

  ## Redemption order

  Checks happen in exactly this order:

    1. base64 decode
    2. split off the trailing 32-byte MAC
    3. structural parse of the header and payload
    4. HMAC verification (constant-time compare)
    5. replay check
    6. expiry check
    7. consume the nonce and deserialize the payload

  Any failure in steps 1–3 yields `{:error, :malformed}`; step 4 yields
  `{:error, :invalid_signature}`. Because the replay check precedes the expiry
  check, a consumed token reports `{:error, :replayed}` forever, even long
  after it would otherwise have expired. The nonce is consumed only on the
  fully successful path.
  """

  use GenServer

  @nonce_bytes 16
  @mac_bytes 32

  @typedoc "A token issued by this server: URL-safe base64, unpadded."
  @type token :: binary()

  @typedoc "Reasons a redemption can fail."
  @type error :: :malformed | :invalid_signature | :replayed | :expired

  @typedoc "A running server: pid or registered name."
  @type server :: GenServer.server()

  defmodule State do
    @moduledoc false
    defstruct [:secret, :clock, consumed: MapSet.new()]
  end

  # ----------------------------------------------------------------------------
  # Public API
  # ----------------------------------------------------------------------------

  @doc """
  Starts the token server.

  ## Options

    * `:secret` (required) — a binary HMAC signing key used for every token
      this server issues and redeems.
    * `:clock` (optional) — a zero-arity function returning a Unix epoch
      second. Defaults to reading `System.os_time(:second)`. This exists purely
      as a test seam for deterministic expiry testing.
    * `:name` (optional) — a name to register the server under.

  Returns `{:ok, pid}`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    secret = Keyword.fetch!(opts, :secret)

    unless is_binary(secret) do
      raise ArgumentError, ":secret must be a binary, got: #{inspect(secret)}"
    end

    clock = Keyword.get(opts, :clock, fn -> System.os_time(:second) end)

    unless is_function(clock, 0) do
      raise ArgumentError, ":clock must be a zero-arity function, got: #{inspect(clock)}"
    end

    gen_opts =
      case Keyword.fetch(opts, :name) do
        {:ok, name} -> [name: name]
        :error -> []
      end

    GenServer.start_link(__MODULE__, {secret, clock}, gen_opts)
  end

  @doc """
  Issues a fresh single-use token for `payload`, valid for `ttl_seconds`.

  `payload` may be any Elixir term. `ttl_seconds` must be a positive integer;
  the token expires at `now + ttl_seconds` (a token whose expiry equals the
  current time is already expired).

  Every call draws a new random nonce, so two tokens are always independent —
  redeeming one never affects the other, even for an identical payload.

  Returns a URL-safe, unpadded base64 binary.
  """
  @spec issue(server(), term(), pos_integer()) :: token()
  def issue(server, payload, ttl_seconds)
      when is_integer(ttl_seconds) and ttl_seconds > 0 do
    GenServer.call(server, {:issue, payload, ttl_seconds})
  end

  @doc """
  Decodes, validates and consumes `token`.

  Returns `{:ok, payload}` the first time a valid, unexpired, not-yet-consumed
  token is redeemed, marking its nonce consumed. Afterwards:

    * `{:error, :replayed}` — the nonce was already consumed (checked before
      expiry, so this wins even for a token that has since expired);
    * `{:error, :expired}` — signature valid, never consumed, but the current
      time is at or past `expires_at`;
    * `{:error, :invalid_signature}` — the frame parses but the HMAC computed
      with this server's secret does not match;
    * `{:error, :malformed}` — anything undecodable: bad base64, too short to
      hold a MAC, a header that disagrees with the remaining bytes, non-binary
      input, and so on.

  No failure result consumes anything.
  """
  @spec redeem(server(), term()) :: {:ok, term()} | {:error, error()}
  def redeem(server, token) do
    GenServer.call(server, {:redeem, token})
  end

  # ----------------------------------------------------------------------------
  # GenServer callbacks
  # ----------------------------------------------------------------------------

  @impl GenServer
  def init({secret, clock}) do
    {:ok, %State{secret: secret, clock: clock, consumed: MapSet.new()}}
  end

  @impl GenServer
  def handle_call({:issue, payload, ttl_seconds}, _from, %State{} = state) do
    now = now(state)
    nonce = :crypto.strong_rand_bytes(@nonce_bytes)
    payload_bytes = :erlang.term_to_binary(payload)

    signed = frame(nonce, now, now + ttl_seconds, payload_bytes)
    token = Base.url_encode64(signed <> mac(state.secret, signed), padding: false)

    {:reply, token, state}
  end

  @impl GenServer
  def handle_call({:redeem, token}, _from, %State{} = state) do
    case verify(token, state) do
      {:ok, nonce, payload_bytes} ->
        payload = :erlang.binary_to_term(payload_bytes, [:safe])
        {:reply, {:ok, payload}, consume(state, nonce)}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  # ----------------------------------------------------------------------------
  # Internals
  # ----------------------------------------------------------------------------

  # Runs the full check pipeline. Returns the nonce and raw payload bytes on
  # success; the caller is responsible for consuming the nonce.
  @spec verify(term(), State.t()) :: {:ok, binary(), binary()} | {:error, error()}
  defp verify(token, %State{} = state) do
    with {:ok, frame} <- decode(token),
         {:ok, signed, given_mac} <- split_mac(frame),
         {:ok, nonce, _issued_at, expires_at, payload_bytes} <- parse(signed),
         :ok <- check_mac(state.secret, signed, given_mac),
         :ok <- check_replay(state, nonce),
         :ok <- check_expiry(state, expires_at) do
      {:ok, nonce, payload_bytes}
    end
  end

  @spec decode(term()) :: {:ok, binary()} | {:error, :malformed}
  defp decode(token) when is_binary(token) do
    case Base.url_decode64(token, padding: false) do
      {:ok, frame} -> {:ok, frame}
      :error -> {:error, :malformed}
    end
  end

  defp decode(_token), do: {:error, :malformed}

  @spec split_mac(binary()) :: {:ok, binary(), binary()} | {:error, :malformed}
  defp split_mac(frame) when byte_size(frame) > @mac_bytes do
    signed_size = byte_size(frame) - @mac_bytes
    <<signed::binary-size(signed_size), given_mac::binary-size(@mac_bytes)>> = frame
    {:ok, signed, given_mac}
  end

  defp split_mac(_frame), do: {:error, :malformed}

  @spec parse(binary()) ::
          {:ok, binary(), integer(), integer(), binary()} | {:error, :malformed}
  defp parse(
         <<nonce::binary-size(@nonce_bytes), issued_at::big-signed-64, expires_at::big-signed-64,
           payload_size::big-unsigned-32, payload_bytes::binary>>
       )
       when byte_size(payload_bytes) == payload_size do
    {:ok, nonce, issued_at, expires_at, payload_bytes}
  end

  defp parse(_signed), do: {:error, :malformed}

  @spec check_mac(binary(), binary(), binary()) :: :ok | {:error, :invalid_signature}
  defp check_mac(secret, signed, given_mac) do
    if secure_compare(mac(secret, signed), given_mac) do
      :ok
    else
      {:error, :invalid_signature}
    end
  end

  @spec check_replay(State.t(), binary()) :: :ok | {:error, :replayed}
  defp check_replay(%State{consumed: consumed}, nonce) do
    if MapSet.member?(consumed, nonce), do: {:error, :replayed}, else: :ok
  end

  @spec check_expiry(State.t(), integer()) :: :ok | {:error, :expired}
  defp check_expiry(%State{} = state, expires_at) do
    # Strictly `<`: a token whose expiry equals the current time is expired.
    if now(state) < expires_at, do: :ok, else: {:error, :expired}
  end

  @spec consume(State.t(), binary()) :: State.t()
  defp consume(%State{consumed: consumed} = state, nonce) do
    %State{state | consumed: MapSet.put(consumed, nonce)}
  end

  @spec frame(binary(), integer(), integer(), binary()) :: binary()
  defp frame(nonce, issued_at, expires_at, payload_bytes) do
    <<nonce::binary-size(@nonce_bytes), issued_at::big-signed-64, expires_at::big-signed-64,
      byte_size(payload_bytes)::big-unsigned-32, payload_bytes::binary>>
  end

  @spec mac(binary(), binary()) :: binary()
  defp mac(secret, data), do: :crypto.mac(:hmac, :sha256, secret, data)

  @spec now(State.t()) :: integer()
  defp now(%State{clock: clock}), do: clock.()

  # Constant-time comparison: never short-circuits on the first differing byte.
  @spec secure_compare(binary(), binary()) :: boolean()
  defp secure_compare(left, right)
       when is_binary(left) and is_binary(right) and byte_size(left) == byte_size(right) do
    xor_bytes(left, right, 0) == 0
  end

  defp secure_compare(_left, _right), do: false

  @spec xor_bytes(binary(), binary(), non_neg_integer()) :: non_neg_integer()
  defp xor_bytes(<<l, left::binary>>, <<r, right::binary>>, acc) do
    xor_bytes(left, right, Bitwise.bor(acc, Bitwise.bxor(l, r)))
  end

  defp xor_bytes(<<>>, <<>>, acc), do: acc
end