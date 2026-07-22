Implement the `handle_call/3` GenServer callback (both clauses, in one definition
group — remember only the first clause carries `@impl true`).

It must handle exactly two request shapes:

1. `{:issue, payload, ttl_seconds}` — build a fresh token for `payload` valid for
   `ttl_seconds` seconds by delegating to the private `build_token/3` helper, and
   reply with that token. Issuing does not change the server state, so the state
   is returned unmodified.

2. `{:redeem, token}` — run the full validation pipeline by delegating to the
   private `verify/2` helper, which returns either `{:ok, nonce, payload_bytes}`
   or `{:error, reason}` where `reason` is one of `:malformed`,
   `:invalid_signature`, `:replayed` or `:expired`.

   * On `{:ok, nonce, payload_bytes}` the token is valid, unexpired and not yet
     consumed: mark it consumed by adding `nonce` to the `consumed` `MapSet` in
     the state, deserialize the payload bytes with the private `deserialize/1`
     helper, and reply `{:ok, payload}` together with the updated state. This is
     the *only* path that consumes a nonce.
   * On `{:error, reason}` reply `{:error, reason}` and leave the state exactly as
     it was — no failure path (`:malformed`, `:invalid_signature`, `:replayed`,
     `:expired`) may consume anything.

Both clauses reply synchronously (`{:reply, reply, state}`); neither should
crash on any input, since `verify/2` already funnels non-binary or undecodable
tokens to `{:error, :malformed}`.

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

  def handle_call({:issue, payload, ttl_seconds}, _from, %State{} = state) do
    # TODO
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

  @spec mac(binary(), binary()) :: binary()
  defp mac(secret, data), do: :crypto.mac(:hmac, :sha256, secret, data)

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