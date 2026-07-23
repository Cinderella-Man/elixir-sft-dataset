# Implement the missing function

The specification below is followed by its complete, tested solution —
minus `mac`, whose clause bodies are all `# TODO`. Supply that one
function; the rest of the module is fixed and must stay exactly as shown.

## The task

Write me an Elixir GenServer called `SingleUseToken` that issues and redeems
signed, expiring, *single-use* tokens. Unlike a purely stateless token, each
token may be redeemed at most once: the server remembers which tokens have been
consumed (in memory, no database) and rejects any replay. Because redemption
mutates shared state, all of it runs through one serializing GenServer.

I need this public API:

- `SingleUseToken.start_link(opts)` where `opts` is a keyword list. It
  recognizes:
  - `:secret` (required) — a binary HMAC signing key used for every token this
    server issues and redeems.
  - `:clock` (optional) — a zero-arity function returning a Unix epoch second.
    When omitted, the current time is read from `System.os_time(:second)`. This
    is purely a test seam for deterministic expiry testing.
  - `:name` (optional) — a name to register the server under.
  It returns `{:ok, pid}`.

- `SingleUseToken.issue(server, payload, ttl_seconds)` where `payload` is any
  Elixir term and `ttl_seconds` is a positive integer. It returns a URL-safe
  binary token (no padding issues, safe to embed in URLs or headers) that
  encodes a fresh unique nonce, the payload, the issue timestamp, the
  expiration timestamp, and an HMAC-SHA256 signature over all of that data.
  Every call produces a token with a distinct random nonce, so two tokens are
  always independent of each other.

- `SingleUseToken.redeem(server, token)` which decodes, validates, and — on
  success — *consumes* the token. Return `{:ok, payload}` the first time a
  valid, unexpired, not-yet-consumed token is redeemed; that redemption marks
  the token's nonce as consumed. Return `{:error, :replayed}` on any subsequent
  redemption of the same token (its nonce is already consumed). Return
  `{:error, :expired}` if the signature is valid and the token has not been
  consumed but the current time is at or past the expiration. Return
  `{:error, :invalid_signature}` if the token structure parses cleanly but the
  HMAC (computed with the server's secret) does not match. Return
  `{:error, :malformed}` for anything that cannot be decoded at all: bad
  base64, too short to contain an HMAC, a header that doesn't match the
  remaining bytes, non-binary token input, and so on.

The check order inside `redeem` is exactly: base64 decode → split off the
trailing 32-byte MAC → structural parse of the header (nonce, issue time,
expiry time) and payload → HMAC verification → replay check → expiry check →
consume the nonce and deserialize the payload. Any failure before HMAC
verification yields `:malformed`. HMAC mismatch yields `:invalid_signature`.
The replay check happens *before* the expiry check, which means a token that
has already been consumed returns `:replayed` forever — even after it would
otherwise have expired. A token that is unexpired-but-consumed returns
`:replayed`; a token that is expired-but-never-consumed returns `:expired`. A
token whose `expires_at` equals the current time is already expired (use strict
`<` on the validity check, not `<=`). The nonce is consumed only on the fully
successful path — none of the failure results (`:malformed`,
`:invalid_signature`, `:replayed`, `:expired`) consume anything.

Implementation requirements:

- Use `:crypto.mac/4` with SHA-256 for signing.
- Generate the nonce with `:crypto.strong_rand_bytes/1`.
- Use `Base.url_encode64/2` with `padding: false` so the output is URL-safe
  without `=` characters.
- The signed region must cover all fields (the nonce, payload bytes, issue
  time, expiry time, plus any length prefix you include for framing) so that
  none of them can be tampered with independently.
- Compare MACs in constant time — don't short-circuit on the first differing
  byte.
- Deserialize the payload with `:erlang.binary_to_term/2` using the `[:safe]`
  option.
- Do not use any external dependencies — only the Elixir standard library and
  OTP.

Give me the complete module in a single file.

## The module with `mac` missing

```elixir
defmodule SingleUseToken do
  @moduledoc """
  A GenServer that issues and redeems signed, expiring, **single-use** tokens.

  Each token carries a fresh random nonce, an arbitrary Elixir payload, an issue
  timestamp, an expiry timestamp, and an HMAC-SHA256 signature computed over all
  of those fields. Tokens are URL-safe base64 strings with no padding.

  Unlike a purely stateless signed token, a token issued by this server may be
  redeemed *at most once*. The server keeps the set of consumed nonces in memory
  (there is no database) and rejects any replay. Because redemption mutates that
  shared state, every redemption is serialized through the single GenServer
  process.

  ## Wire format

      token = url_encode64(header <> payload_bytes <> mac, padding: false)

      header  = <<nonce::binary-size(16), issued_at::64, expires_at::64,
                  payload_size::32>>
      mac     = hmac_sha256(secret, header <> payload_bytes)   # 32 bytes

  The MAC covers the nonce, both timestamps, the payload length prefix and the
  payload bytes, so no field can be tampered with independently.

  ## Redemption order

  `redeem/2` performs its checks in exactly this order:

  base64 decode → split off the trailing 32-byte MAC → structural parse of the
  header and payload → HMAC verification → replay check → expiry check → consume
  the nonce and deserialize the payload.

  Any failure before HMAC verification yields `{:error, :malformed}`; an HMAC
  mismatch yields `{:error, :invalid_signature}`. Because the replay check runs
  before the expiry check, an already-consumed token returns `{:error, :replayed}`
  forever, even long after it would otherwise have expired. The nonce is consumed
  only on the fully successful path.

  ## Example

      {:ok, pid} = SingleUseToken.start_link(secret: "s3cr3t")
      token = SingleUseToken.issue(pid, %{user_id: 7}, 300)
      {:ok, %{user_id: 7}} = SingleUseToken.redeem(pid, token)
      {:error, :replayed} = SingleUseToken.redeem(pid, token)
  """

  use GenServer

  @nonce_size 16
  @mac_size 32

  @typedoc "An opaque, URL-safe, single-use token."
  @type token :: binary()

  @typedoc "Reasons a redemption can fail."
  @type error :: :malformed | :invalid_signature | :replayed | :expired

  defmodule State do
    @moduledoc false

    defstruct [:secret, :clock, consumed: MapSet.new()]

    @type t :: %__MODULE__{
            secret: binary(),
            clock: (-> integer()),
            consumed: MapSet.t(binary())
          }
  end

  # ------------------------------------------------------------------
  # Public API
  # ------------------------------------------------------------------

  @doc """
  Starts the token server.

  Options:

    * `:secret` (required) — a binary HMAC signing key used for every token this
      server issues and redeems.
    * `:clock` (optional) — a zero-arity function returning a Unix epoch second.
      Defaults to reading `System.os_time(:second)`. This exists purely as a test
      seam for deterministic expiry testing.
    * `:name` (optional) — a name to register the server under.

  Returns `{:ok, pid}`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    secret = Keyword.fetch!(opts, :secret)

    if not is_binary(secret) do
      raise ArgumentError, ":secret must be a binary, got: #{inspect(secret)}"
    end

    clock = Keyword.get(opts, :clock, fn -> System.os_time(:second) end)

    if not is_function(clock, 0) do
      raise ArgumentError, ":clock must be a zero-arity function, got: #{inspect(clock)}"
    end

    server_opts =
      case Keyword.fetch(opts, :name) do
        {:ok, name} -> [name: name]
        :error -> []
      end

    GenServer.start_link(__MODULE__, {secret, clock}, server_opts)
  end

  @doc """
  Issues a fresh single-use token for `payload`, valid for `ttl_seconds` seconds.

  `payload` may be any Elixir term; `ttl_seconds` must be a positive integer. The
  returned binary is URL-safe base64 without padding and encodes a fresh random
  nonce, the payload, the issue time, the expiry time and an HMAC-SHA256
  signature over all of them. Two calls never produce the same token, even for
  identical payloads, because each carries a distinct nonce.
  """
  @spec issue(GenServer.server(), term(), pos_integer()) :: token()
  def issue(server, payload, ttl_seconds)
      when is_integer(ttl_seconds) and ttl_seconds > 0 do
    GenServer.call(server, {:issue, payload, ttl_seconds})
  end

  @doc """
  Decodes, validates and consumes `token`.

  Returns `{:ok, payload}` the first time a valid, unexpired, not-yet-consumed
  token is redeemed, marking its nonce consumed. Subsequent redemptions of the
  same token return `{:error, :replayed}`.

  Failure reasons:

    * `{:error, :malformed}` — the token cannot be decoded at all (bad base64,
      too short to hold a MAC, header inconsistent with the remaining bytes,
      non-binary input, …).
    * `{:error, :invalid_signature}` — the structure parses but the HMAC computed
      with this server's secret does not match.
    * `{:error, :replayed}` — the nonce has already been consumed.
    * `{:error, :expired}` — the signature is valid and the nonce is unconsumed,
      but the current time is at or past `expires_at`.

  No failure path consumes anything.
  """
  @spec redeem(GenServer.server(), term()) :: {:ok, term()} | {:error, error()}
  def redeem(server, token) do
    GenServer.call(server, {:redeem, token})
  end

  # ------------------------------------------------------------------
  # GenServer callbacks
  # ------------------------------------------------------------------

  @impl true
  def init({secret, clock}) do
    {:ok, %State{secret: secret, clock: clock, consumed: MapSet.new()}}
  end

  @impl true
  def handle_call({:issue, payload, ttl_seconds}, _from, %State{} = state) do
    {:reply, build_token(state, payload, ttl_seconds), state}
  end

  def handle_call({:redeem, token}, _from, %State{} = state) do
    case verify(state, token) do
      {:ok, nonce, payload_bytes} ->
        consumed = MapSet.put(state.consumed, nonce)
        {:reply, {:ok, deserialize(payload_bytes)}, %State{state | consumed: consumed}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  # ------------------------------------------------------------------
  # Internals
  # ------------------------------------------------------------------

  @spec build_token(State.t(), term(), pos_integer()) :: token()
  defp build_token(%State{secret: secret, clock: clock}, payload, ttl_seconds) do
    nonce = :crypto.strong_rand_bytes(@nonce_size)
    issued_at = clock.()
    expires_at = issued_at + ttl_seconds
    payload_bytes = :erlang.term_to_binary(payload)

    signed =
      <<nonce::binary-size(@nonce_size), issued_at::signed-integer-64,
        expires_at::signed-integer-64, byte_size(payload_bytes)::unsigned-integer-32,
        payload_bytes::binary>>

    Base.url_encode64(signed <> mac(secret, signed), padding: false)
  end

  # Runs the full check pipeline. Returns the nonce and raw payload bytes so the
  # caller can consume the nonce only on the fully successful path.
  @spec verify(State.t(), term()) :: {:ok, binary(), binary()} | {:error, error()}
  defp verify(%State{} = state, token) when is_binary(token) do
    with {:ok, raw} <- decode(token),
         {:ok, signed, candidate_mac} <- split_mac(raw),
         {:ok, nonce, expires_at, payload_bytes} <- parse(signed),
         :ok <- check_mac(state.secret, signed, candidate_mac),
         :ok <- check_replay(state.consumed, nonce),
         :ok <- check_expiry(state.clock.(), expires_at) do
      {:ok, nonce, payload_bytes}
    end
  end

  defp verify(%State{}, _token), do: {:error, :malformed}

  @spec decode(binary()) :: {:ok, binary()} | {:error, :malformed}
  defp decode(token) do
    case Base.url_decode64(token, padding: false) do
      {:ok, raw} -> {:ok, raw}
      :error -> {:error, :malformed}
    end
  end

  @spec split_mac(binary()) :: {:ok, binary(), binary()} | {:error, :malformed}
  defp split_mac(raw) when byte_size(raw) > @mac_size do
    signed_size = byte_size(raw) - @mac_size
    {:ok, binary_part(raw, 0, signed_size), binary_part(raw, signed_size, @mac_size)}
  end

  defp split_mac(_raw), do: {:error, :malformed}

  @spec parse(binary()) :: {:ok, binary(), integer(), binary()} | {:error, :malformed}
  defp parse(
         <<nonce::binary-size(@nonce_size), _issued_at::signed-integer-64,
           expires_at::signed-integer-64, payload_size::unsigned-integer-32,
           payload_bytes::binary>>
       )
       when byte_size(payload_bytes) == payload_size do
    {:ok, nonce, expires_at, payload_bytes}
  end

  defp parse(_signed), do: {:error, :malformed}

  @spec check_mac(binary(), binary(), binary()) :: :ok | {:error, :invalid_signature}
  defp check_mac(secret, signed, candidate_mac) do
    if constant_time_equal?(mac(secret, signed), candidate_mac) do
      :ok
    else
      {:error, :invalid_signature}
    end
  end

  @spec check_replay(MapSet.t(binary()), binary()) :: :ok | {:error, :replayed}
  defp check_replay(consumed, nonce) do
    if MapSet.member?(consumed, nonce), do: {:error, :replayed}, else: :ok
  end

  @spec check_expiry(integer(), integer()) :: :ok | {:error, :expired}
  defp check_expiry(now, expires_at) do
    if now < expires_at, do: :ok, else: {:error, :expired}
  end

  @spec deserialize(binary()) :: term()
  defp deserialize(payload_bytes) do
    :erlang.binary_to_term(payload_bytes, [:safe])
  end

  defp mac(secret, data) do
    # TODO
  end

  # Non-short-circuiting comparison: every byte pair is always examined and the
  # per-byte differences are accumulated, so timing does not leak where two MACs
  # first differ. Binaries of differing size are rejected outright.
  @spec constant_time_equal?(binary(), binary()) :: boolean()
  defp constant_time_equal?(left, right)
       when is_binary(left) and is_binary(right) and byte_size(left) == byte_size(right) do
    diff =
      left
      |> :binary.bin_to_list()
      |> Enum.zip(:binary.bin_to_list(right))
      |> Enum.reduce(0, fn {a, b}, acc -> acc + abs(a - b) end)

    diff === 0
  end

  defp constant_time_equal?(_left, _right), do: false
end
```

Output only `mac` (with any `@doc`/`@spec`/`@impl` lines that belong
directly above it) — the single function, not the module.
