# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

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

## Test harness — implement the `# TODO` test

```elixir
defmodule SingleUseTokenTest do
  use ExUnit.Case, async: false

  # --- Fake clock for deterministic expiry testing ---

  defmodule Clock do
    use Agent

    def start_link(initial \\ 0) do
      Agent.start_link(fn -> initial end, name: __MODULE__)
    end

    def now, do: Agent.get(__MODULE__, & &1)
    def advance(seconds), do: Agent.update(__MODULE__, &(&1 + seconds))
    def set(seconds), do: Agent.update(__MODULE__, fn _ -> seconds end)
  end

  setup do
    start_supervised!({Clock, 1_000_000})

    server =
      start_supervised!({SingleUseToken, secret: "server-secret", clock: &Clock.now/0})

    %{server: server}
  end

  # -------------------------------------------------------
  # Basic round-trip
  # -------------------------------------------------------

  test "issued token redeems successfully", %{server: server} do
    token = SingleUseToken.issue(server, %{user_id: 42}, 300)
    assert is_binary(token)
    assert {:ok, %{user_id: 42}} = SingleUseToken.redeem(server, token)
  end

  test "payload is preserved exactly through round-trip", %{server: server} do
    payload = %{role: "admin", sub: "user:99", meta: [1, 2, 3]}
    token = SingleUseToken.issue(server, payload, 60)
    assert {:ok, ^payload} = SingleUseToken.redeem(server, token)
  end

  test "token is URL-safe (no +, /, or = characters)", %{server: server} do
    token = SingleUseToken.issue(server, "hello", 60)
    refute String.contains?(token, "+")
    refute String.contains?(token, "/")
    refute String.contains?(token, "=")
  end

  # -------------------------------------------------------
  # Single use / replay
  # -------------------------------------------------------

  test "a token can be redeemed only once; the second redemption is :replayed",
       %{server: server} do
    token = SingleUseToken.issue(server, "once", 300)
    assert {:ok, "once"} = SingleUseToken.redeem(server, token)
    assert {:error, :replayed} = SingleUseToken.redeem(server, token)
  end

  test "consuming one token does not consume an independently issued token",
       %{server: server} do
    t1 = SingleUseToken.issue(server, "a", 300)
    t2 = SingleUseToken.issue(server, "b", 300)

    assert {:ok, "a"} = SingleUseToken.redeem(server, t1)
    # t2 is unaffected by t1's redemption.
    assert {:ok, "b"} = SingleUseToken.redeem(server, t2)
  end

  test "replay check takes precedence over expiry", %{server: server} do
    token = SingleUseToken.issue(server, "x", 100)
    assert {:ok, "x"} = SingleUseToken.redeem(server, token)

    # Advance past the token's expiry; a consumed token stays :replayed.
    Clock.advance(500)
    assert {:error, :replayed} = SingleUseToken.redeem(server, token)
  end

  # -------------------------------------------------------
  # Nonce independence for identical issuance arguments
  # -------------------------------------------------------

  test "two tokens issued with the same payload and ttl are different binaries",
       %{server: server} do
    # Each call mints a fresh random nonce, so identical arguments still yield
    # distinct tokens even though the clock is frozen.
    t1 = SingleUseToken.issue(server, %{user_id: 7}, 300)
    t2 = SingleUseToken.issue(server, %{user_id: 7}, 300)

    refute t1 == t2
  end

  test "redeeming a token does not consume another token with the identical payload",
       %{server: server} do
    t1 = SingleUseToken.issue(server, %{user_id: 7}, 300)
    t2 = SingleUseToken.issue(server, %{user_id: 7}, 300)

    assert {:ok, %{user_id: 7}} = SingleUseToken.redeem(server, t1)
    # Distinct nonces: t1's redemption leaves t2 fully redeemable.
    assert {:ok, %{user_id: 7}} = SingleUseToken.redeem(server, t2)

    # Each token is now individually consumed.
    assert {:error, :replayed} = SingleUseToken.redeem(server, t1)
    assert {:error, :replayed} = SingleUseToken.redeem(server, t2)
  end

  # -------------------------------------------------------
  # Default clock (`:clock` omitted)
  # -------------------------------------------------------

  test "server started without :clock issues and redeems tokens" do
    server =
      start_supervised!(
        Supervisor.child_spec({SingleUseToken, secret: "default-clock-secret"},
          id: :default_clock_server
        )
      )

    token = SingleUseToken.issue(server, %{user_id: 3}, 300)
    assert {:ok, %{user_id: 3}} = SingleUseToken.redeem(server, token)
    assert {:error, :replayed} = SingleUseToken.redeem(server, token)
  end

  test "the omitted :clock defaults to Unix epoch seconds" do
    secret = "epoch-secret"
    now = System.os_time(:second)

    # Issues on the default clock; the two peers share the secret, so the tokens
    # verify there and are judged against a known epoch-second time.
    issuer =
      start_supervised!(
        Supervisor.child_spec({SingleUseToken, secret: secret}, id: :epoch_issuer)
      )

    present_peer =
      start_supervised!(
        Supervisor.child_spec({SingleUseToken, secret: secret, clock: fn -> now end},
          id: :epoch_present_peer
        )
      )

    future_peer =
      start_supervised!(
        Supervisor.child_spec({SingleUseToken, secret: secret, clock: fn -> now + 3_600 end},
          id: :epoch_future_peer
        )
      )

    # A 60-second token issued "now" is still valid at epoch second `now` ...
    assert {:ok, "epoch"} =
             SingleUseToken.redeem(present_peer, SingleUseToken.issue(issuer, "epoch", 60))

    # ... and expired an hour later, which only holds if the default clock ticks
    # in epoch seconds rather than some other unit or epoch.
    assert {:error, :expired} =
             SingleUseToken.redeem(future_peer, SingleUseToken.issue(issuer, "epoch", 60))
  end

  # -------------------------------------------------------
  # Expiry
  # -------------------------------------------------------

  test "token is valid just before expiry", %{server: server} do
    token = SingleUseToken.issue(server, "data", 100)
    Clock.advance(99)
    assert {:ok, "data"} = SingleUseToken.redeem(server, token)
  end

  test "expired, never-consumed token returns :expired", %{server: server} do
    # TODO
  end

  test "token expires exactly at ttl boundary", %{server: server} do
    token = SingleUseToken.issue(server, "data", 50)
    Clock.advance(50)
    assert {:error, :expired} = SingleUseToken.redeem(server, token)
  end

  test "an expired token is not consumed, so it never becomes :replayed",
       %{server: server} do
    token = SingleUseToken.issue(server, "data", 100)
    Clock.advance(101)
    assert {:error, :expired} = SingleUseToken.redeem(server, token)
    # Still :expired, not :replayed — the failed redemption consumed nothing.
    assert {:error, :expired} = SingleUseToken.redeem(server, token)
  end

  # -------------------------------------------------------
  # Signature validation
  # -------------------------------------------------------

  test "a token issued by another server (different secret) is :invalid_signature",
       %{server: server} do
    other =
      start_supervised!(
        Supervisor.child_spec(
          {SingleUseToken, secret: "different-secret", clock: &Clock.now/0},
          id: :other_server
        )
      )

    token = SingleUseToken.issue(server, "x", 300)
    assert {:error, :invalid_signature} = SingleUseToken.redeem(other, token)
  end

  test "tampered token returns :invalid_signature", %{server: server} do
    token = SingleUseToken.issue(server, %{role: "user"}, 300)

    tampered =
      token
      |> String.graphemes()
      |> List.update_at(div(byte_size(token), 2), fn
        "A" -> "B"
        _ -> "A"
      end)
      |> Enum.join()

    assert {:error, :invalid_signature} = SingleUseToken.redeem(server, tampered)
  end

  test "no byte of the signed region can be rewritten without rejection",
       %{server: server} do
    # The signed region is everything ahead of the trailing 32-byte MAC: the
    # nonce, the issue and expiry timestamps, any length prefix and the payload
    # bytes. Rewriting any one of those bytes must be caught either by the
    # structural parse (:malformed) or by HMAC verification
    # (:invalid_signature) — and, because HMAC verification runs before the
    # expiry check, never by expiry and never by acceptance. In particular a
    # rewritten expiry timestamp cannot buy an attacker extra lifetime.
    token = SingleUseToken.issue(server, %{role: "user"}, 100)
    {:ok, raw} = Base.url_decode64(token, padding: false)
    signed_size = byte_size(raw) - 32
    assert signed_size > 0

    for index <- 0..(signed_size - 1), value <- rewrites(:binary.at(raw, index)) do
      mutated = Base.url_encode64(put_byte(raw, index, value), padding: false)
      assert {:error, reason} = SingleUseToken.redeem(server, mutated)
      assert reason in [:malformed, :invalid_signature]
    end

    # None of those rejected redemptions consumed anything, so the pristine
    # token is still redeemable exactly once.
    assert {:ok, %{role: "user"}} = SingleUseToken.redeem(server, token)
    assert {:error, :replayed} = SingleUseToken.redeem(server, token)
  end

  test "no byte of the trailing MAC can be rewritten without rejection",
       %{server: server} do
    # Rewriting a MAC byte leaves the header consistent with the remaining
    # bytes, so the structure still parses cleanly and the failure is
    # attributed to the signature rather than to decoding.
    token = SingleUseToken.issue(server, %{role: "user"}, 100)
    {:ok, raw} = Base.url_decode64(token, padding: false)
    signed_size = byte_size(raw) - 32
    assert signed_size > 0

    for index <- signed_size..(byte_size(raw) - 1), value <- rewrites(:binary.at(raw, index)) do
      mutated = Base.url_encode64(put_byte(raw, index, value), padding: false)
      assert {:error, :invalid_signature} = SingleUseToken.redeem(server, mutated)
    end

    assert {:ok, %{role: "user"}} = SingleUseToken.redeem(server, token)
  end

  # -------------------------------------------------------
  # Malformed input
  # -------------------------------------------------------

  test "empty string returns :malformed", %{server: server} do
    assert {:error, :malformed} = SingleUseToken.redeem(server, "")
  end

  test "random binary returns :malformed", %{server: server} do
    assert {:error, :malformed} = SingleUseToken.redeem(server, "notavalidtoken!!!")
  end

  test "truncated token returns :malformed", %{server: server} do
    token = SingleUseToken.issue(server, "hello", 60)
    truncated = binary_part(token, 0, div(byte_size(token), 2))
    assert {:error, :malformed} = SingleUseToken.redeem(server, truncated)
  end

  test "valid base64 but garbage content returns :malformed", %{server: server} do
    garbage = Base.url_encode64("this is not a valid token structure", padding: false)
    assert {:error, :malformed} = SingleUseToken.redeem(server, garbage)
  end

  test "non-binary token input returns :malformed", %{server: server} do
    assert {:error, :malformed} = SingleUseToken.redeem(server, 12345)
  end

  # -------------------------------------------------------
  # Various payload types
  # -------------------------------------------------------

  test "supports atom payload", %{server: server} do
    token = SingleUseToken.issue(server, :hello, 60)
    assert {:ok, :hello} = SingleUseToken.redeem(server, token)
  end

  test "supports integer payload", %{server: server} do
    token = SingleUseToken.issue(server, 12345, 60)
    assert {:ok, 12345} = SingleUseToken.redeem(server, token)
  end

  test "supports list payload", %{server: server} do
    token = SingleUseToken.issue(server, [1, "two", :three], 60)
    assert {:ok, [1, "two", :three]} = SingleUseToken.redeem(server, token)
  end

  test "supports deeply nested map payload", %{server: server} do
    payload = %{a: %{b: %{c: "deep"}}}
    token = SingleUseToken.issue(server, payload, 60)
    assert {:ok, ^payload} = SingleUseToken.redeem(server, token)
  end

  # --- Byte-rewriting helpers ---

  # Replacement values for one byte, chosen so that whichever way a timestamp
  # field is laid out, at least one rewrite pushes it far into the future while
  # others clear or invert it. Values equal to the original byte are dropped so
  # every rewrite really changes the token.
  defp rewrites(byte) do
    [:erlang.bxor(byte, 0xFF), 0x00, 0x7F, 0xFF]
    |> Enum.uniq()
    |> Enum.reject(&(&1 == byte))
  end

  defp put_byte(raw, index, value) do
    <<prefix::binary-size(^index), _old, rest::binary>> = raw
    prefix <> <<value>> <> rest
  end
end
```
