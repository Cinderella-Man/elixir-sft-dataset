# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule OneTimeTokenStore do
  @moduledoc """
  A GenServer that manages single-use tokens with absolute expiration.

  Each token holds a payload and an absolute deadline computed at creation
  time. Tokens can be verified (non-destructive) or redeemed (one-time
  consumption). Expiration is absolute — accessing a token never extends
  its lifetime.

  ## Options

    * `:name`               - process registration name (optional)
    * `:default_ttl_ms`     - default token lifetime in ms (default: 3_600_000 / 1 hour)
    * `:cleanup_interval_ms`- how often the sweep runs in ms (default: 60_000 / 1 min)
    * `:clock`              - zero-arity fn returning current time in ms;
                              defaults to `fn -> System.monotonic_time(:millisecond) end`

  ## Examples

      {:ok, pid} = OneTimeTokenStore.start_link(default_ttl_ms: 5_000)

      {:ok, token} = OneTimeTokenStore.mint(pid, %{user_id: 42, action: :reset_password})
      {:ok, %{user_id: 42, action: :reset_password}} = OneTimeTokenStore.verify(pid, token)

      {:ok, %{user_id: 42, action: :reset_password}} = OneTimeTokenStore.redeem(pid, token)
      {:error, :not_found} = OneTimeTokenStore.redeem(pid, token)   # already consumed
  """

  use GenServer

  # ---------------------------------------------------------------------------
  # Types
  # ---------------------------------------------------------------------------

  @type server :: GenServer.server()
  @type token_id :: String.t()
  @type payload :: term()

  @type token :: %{
          payload: payload(),
          expires_at: integer()
        }

  @type state :: %{
          tokens: %{token_id() => token()},
          default_ttl_ms: non_neg_integer(),
          cleanup_interval_ms: non_neg_integer(),
          clock: (-> integer())
        }

  # ---------------------------------------------------------------------------
  # Defaults
  # ---------------------------------------------------------------------------

  @default_ttl_ms 3_600_000
  @default_cleanup_interval_ms 60_000
  @default_clock &__MODULE__.__default_clock__/0

  @doc false
  def __default_clock__, do: System.monotonic_time(:millisecond)

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts the `OneTimeTokenStore` process.

  ## Options

    * `:name`                - passed directly to `GenServer.start_link/3`
    * `:default_ttl_ms`      - token lifetime (default #{@default_ttl_ms} ms)
    * `:cleanup_interval_ms` - sweep interval (default #{@default_cleanup_interval_ms} ms)
    * `:clock`               - zero-arity fn returning current time in ms
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name_opt, init_opts} =
      case Keyword.pop(opts, :name) do
        {nil, rest} -> {[], rest}
        {name, rest} -> {[name: name], rest}
      end

    GenServer.start_link(__MODULE__, init_opts, name_opt)
  end

  @doc """
  Creates a new token containing `payload`.

  Returns `{:ok, token_id}`. The token expires at `now + ttl_ms` and is
  never extended — this is an absolute deadline.

  ## Options

    * `:ttl_ms` - override the default TTL for this specific token
  """
  @spec mint(server(), payload(), keyword()) :: {:ok, token_id()}
  def mint(server, payload, opts \\ []) do
    GenServer.call(server, {:mint, payload, opts})
  end

  @doc """
  Checks whether `token_id` is valid without consuming it.

  Returns `{:ok, payload}` if the token exists and has not expired or
  been redeemed, or `{:error, :not_found}` otherwise.
  """
  @spec verify(server(), token_id()) :: {:ok, payload()} | {:error, :not_found}
  def verify(server, token_id) do
    GenServer.call(server, {:verify, token_id})
  end

  @doc """
  Consumes a valid token, returning its payload and permanently removing it.

  Returns `{:ok, payload}` on success, or `{:error, :not_found}` if the
  token doesn't exist, was already redeemed, or has expired.
  """
  @spec redeem(server(), token_id()) :: {:ok, payload()} | {:error, :not_found}
  def redeem(server, token_id) do
    GenServer.call(server, {:redeem, token_id})
  end

  @doc """
  Invalidates a token without redeeming it.

  Always returns `:ok`, even if the token did not exist.
  """
  @spec revoke(server(), token_id()) :: :ok
  def revoke(server, token_id) do
    GenServer.call(server, {:revoke, token_id})
  end

  @doc """
  Returns the number of tokens that are still valid (not expired, not
  redeemed, not revoked).
  """
  @spec active_count(server()) :: non_neg_integer()
  def active_count(server) do
    GenServer.call(server, :active_count)
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl GenServer
  def init(opts) do
    default_ttl_ms = Keyword.get(opts, :default_ttl_ms, @default_ttl_ms)
    cleanup_interval_ms = Keyword.get(opts, :cleanup_interval_ms, @default_cleanup_interval_ms)
    clock = Keyword.get(opts, :clock, @default_clock)

    state = %{
      tokens: %{},
      default_ttl_ms: default_ttl_ms,
      cleanup_interval_ms: cleanup_interval_ms,
      clock: clock
    }

    schedule_cleanup(cleanup_interval_ms)
    {:ok, state}
  end

  @impl GenServer
  def handle_call({:mint, payload, opts}, _from, state) do
    token_id = generate_token_id()
    now = state.clock.()
    ttl_ms = Keyword.get(opts, :ttl_ms, state.default_ttl_ms)

    token = %{payload: payload, expires_at: now + ttl_ms}
    new_tokens = Map.put(state.tokens, token_id, token)

    {:reply, {:ok, token_id}, %{state | tokens: new_tokens}}
  end

  def handle_call({:verify, token_id}, _from, state) do
    now = state.clock.()

    case fetch_live_token(state.tokens, token_id, now) do
      {:ok, token} ->
        {:reply, {:ok, token.payload}, state}

      :expired ->
        new_tokens = Map.delete(state.tokens, token_id)
        {:reply, {:error, :not_found}, %{state | tokens: new_tokens}}

      :missing ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:redeem, token_id}, _from, state) do
    now = state.clock.()

    case fetch_live_token(state.tokens, token_id, now) do
      {:ok, token} ->
        new_tokens = Map.delete(state.tokens, token_id)
        {:reply, {:ok, token.payload}, %{state | tokens: new_tokens}}

      :expired ->
        new_tokens = Map.delete(state.tokens, token_id)
        {:reply, {:error, :not_found}, %{state | tokens: new_tokens}}

      :missing ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:revoke, token_id}, _from, state) do
    new_tokens = Map.delete(state.tokens, token_id)
    {:reply, :ok, %{state | tokens: new_tokens}}
  end

  def handle_call(:active_count, _from, state) do
    now = state.clock.()

    count =
      Enum.count(state.tokens, fn {_id, token} ->
        not expired?(token, now)
      end)

    {:reply, count, state}
  end

  @impl GenServer
  def handle_info(:cleanup, state) do
    now = state.clock.()

    surviving_tokens =
      Map.filter(state.tokens, fn {_id, token} ->
        not expired?(token, now)
      end)

    schedule_cleanup(state.cleanup_interval_ms)
    {:noreply, %{state | tokens: surviving_tokens}}
  end

  def handle_info(msg, state) do
    require Logger
    Logger.warning("#{__MODULE__} received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  @spec generate_token_id() :: token_id()
  defp generate_token_id do
    :crypto.strong_rand_bytes(16)
    |> Base.url_encode64(padding: false)
  end

  defp schedule_cleanup(interval_ms) when is_integer(interval_ms) do
    Process.send_after(self(), :cleanup, interval_ms)
  end

  defp schedule_cleanup(_), do: :ok

  @spec expired?(token(), integer()) :: boolean()
  defp expired?(token, now) do
    now >= token.expires_at
  end

  @spec fetch_live_token(%{token_id() => token()}, token_id(), integer()) ::
          {:ok, token()} | :expired | :missing
  defp fetch_live_token(tokens, token_id, now) do
    case Map.fetch(tokens, token_id) do
      {:ok, token} ->
        if expired?(token, now), do: :expired, else: {:ok, token}

      :error ->
        :missing
    end
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule OneTimeTokenStoreTest do
  use ExUnit.Case, async: false

  # --- Fake clock for deterministic testing ---

  defmodule Clock do
    use Agent

    def start_link(initial \\ 0) do
      Agent.start_link(fn -> initial end, name: __MODULE__)
    end

    def now, do: Agent.get(__MODULE__, & &1)
    def advance(ms), do: Agent.update(__MODULE__, &(&1 + ms))
    def set(ms), do: Agent.update(__MODULE__, fn _ -> ms end)
  end

  setup do
    start_supervised!({Clock, 0})

    {:ok, pid} =
      OneTimeTokenStore.start_link(
        clock: &Clock.now/0,
        default_ttl_ms: 1_000,
        cleanup_interval_ms: :infinity
      )

    %{store: pid}
  end

  # -------------------------------------------------------
  # Basic mint / verify / redeem
  # -------------------------------------------------------

  test "mint returns a unique token id", %{store: store} do
    assert {:ok, id1} = OneTimeTokenStore.mint(store, %{action: :reset})
    assert {:ok, id2} = OneTimeTokenStore.mint(store, %{action: :invite})

    assert is_binary(id1)
    assert is_binary(id2)
    assert id1 != id2
  end

  test "verify retrieves the token payload without consuming it", %{store: store} do
    {:ok, id} = OneTimeTokenStore.mint(store, %{user: "alice", action: :reset})

    assert {:ok, %{user: "alice", action: :reset}} = OneTimeTokenStore.verify(store, id)
    # Still available after verify
    assert {:ok, %{user: "alice", action: :reset}} = OneTimeTokenStore.verify(store, id)
  end

  test "verify returns error for unknown token", %{store: store} do
    assert {:error, :not_found} = OneTimeTokenStore.verify(store, "nonexistent")
  end

  test "redeem returns payload and removes the token", %{store: store} do
    {:ok, id} = OneTimeTokenStore.mint(store, %{user: "alice"})

    assert {:ok, %{user: "alice"}} = OneTimeTokenStore.redeem(store, id)
    # Second redeem fails — token is consumed
    assert {:error, :not_found} = OneTimeTokenStore.redeem(store, id)
  end

  test "redeem returns error for unknown token", %{store: store} do
    assert {:error, :not_found} = OneTimeTokenStore.redeem(store, "nonexistent")
  end

  test "verify fails after redeem", %{store: store} do
    {:ok, id} = OneTimeTokenStore.mint(store, %{code: "ABC"})

    assert {:ok, _} = OneTimeTokenStore.redeem(store, id)
    assert {:error, :not_found} = OneTimeTokenStore.verify(store, id)
  end

  # -------------------------------------------------------
  # Revoke
  # -------------------------------------------------------

  test "revoke removes the token", %{store: store} do
    {:ok, id} = OneTimeTokenStore.mint(store, %{user: "alice"})
    assert {:ok, _} = OneTimeTokenStore.verify(store, id)

    assert :ok = OneTimeTokenStore.revoke(store, id)
    assert {:error, :not_found} = OneTimeTokenStore.verify(store, id)
    assert {:error, :not_found} = OneTimeTokenStore.redeem(store, id)
  end

  test "revoke returns :ok for unknown token", %{store: store} do
    assert :ok = OneTimeTokenStore.revoke(store, "nonexistent")
  end

  # -------------------------------------------------------
  # Absolute expiration (NOT sliding)
  # -------------------------------------------------------

  test "token expires after its TTL", %{store: store} do
    {:ok, id} = OneTimeTokenStore.mint(store, %{user: "alice"})

    Clock.advance(1_001)

    assert {:error, :not_found} = OneTimeTokenStore.verify(store, id)
    assert {:error, :not_found} = OneTimeTokenStore.redeem(store, id)
  end

  test "token is still alive just before TTL", %{store: store} do
    {:ok, id} = OneTimeTokenStore.mint(store, %{user: "alice"})

    Clock.advance(999)

    assert {:ok, %{user: "alice"}} = OneTimeTokenStore.verify(store, id)
  end

  test "verify does NOT extend the expiration (absolute, not sliding)", %{store: store} do
    {:ok, id} = OneTimeTokenStore.mint(store, %{user: "alice"})

    # Verify at 800ms — still alive
    Clock.advance(800)
    assert {:ok, _} = OneTimeTokenStore.verify(store, id)

    # Another 300ms later (total 1100ms from creation) — expired
    # In a sliding-window store, the verify at 800ms would have extended it.
    # Here it must NOT extend.
    Clock.advance(300)
    assert {:error, :not_found} = OneTimeTokenStore.verify(store, id)
  end

  # -------------------------------------------------------
  # Per-token TTL override
  # -------------------------------------------------------

  test "mint accepts per-token :ttl_ms override", %{store: store} do
    {:ok, short_id} = OneTimeTokenStore.mint(store, %{type: :short}, ttl_ms: 200)
    {:ok, long_id} = OneTimeTokenStore.mint(store, %{type: :long}, ttl_ms: 5_000)

    Clock.advance(300)

    assert {:error, :not_found} = OneTimeTokenStore.verify(store, short_id)
    assert {:ok, %{type: :long}} = OneTimeTokenStore.verify(store, long_id)
  end

  # -------------------------------------------------------
  # Token independence
  # -------------------------------------------------------

  test "tokens are fully independent", %{store: store} do
    {:ok, id_a} = OneTimeTokenStore.mint(store, %{user: "alice"})

    Clock.advance(500)
    {:ok, id_b} = OneTimeTokenStore.mint(store, %{user: "bob"})

    # At time 1001: alice expired, bob still has ~500ms
    Clock.advance(501)

    assert {:error, :not_found} = OneTimeTokenStore.verify(store, id_a)
    assert {:ok, %{user: "bob"}} = OneTimeTokenStore.verify(store, id_b)
  end

  test "redeeming one token does not affect another", %{store: store} do
    {:ok, id_a} = OneTimeTokenStore.mint(store, %{user: "alice"})
    {:ok, id_b} = OneTimeTokenStore.mint(store, %{user: "bob"})

    OneTimeTokenStore.redeem(store, id_a)

    assert {:error, :not_found} = OneTimeTokenStore.verify(store, id_a)
    assert {:ok, %{user: "bob"}} = OneTimeTokenStore.verify(store, id_b)
  end

  # -------------------------------------------------------
  # active_count
  # -------------------------------------------------------

  test "active_count reflects only non-expired, non-redeemed tokens", %{store: store} do
    {:ok, id1} = OneTimeTokenStore.mint(store, %{n: 1})
    {:ok, _id2} = OneTimeTokenStore.mint(store, %{n: 2})
    {:ok, _id3} = OneTimeTokenStore.mint(store, %{n: 3})

    assert OneTimeTokenStore.active_count(store) == 3

    # Redeem one
    OneTimeTokenStore.redeem(store, id1)
    assert OneTimeTokenStore.active_count(store) == 2

    # Expire the remaining two
    Clock.advance(1_001)
    assert OneTimeTokenStore.active_count(store) == 0
  end

  # -------------------------------------------------------
  # Cleanup (memory leak prevention)
  # -------------------------------------------------------

  test "expired tokens are cleaned up by sweep", %{store: store} do
    # TODO
  end

  test "cleanup only removes expired tokens, keeps active ones", %{store: store} do
    {:ok, old_id} = OneTimeTokenStore.mint(store, %{user: "old"})

    Clock.advance(900)
    {:ok, new_id} = OneTimeTokenStore.mint(store, %{user: "new"})

    Clock.advance(101)

    send(store, :cleanup)

    # Only the still-valid token survives the sweep.
    assert OneTimeTokenStore.active_count(store) == 1

    assert {:error, :not_found} = OneTimeTokenStore.verify(store, old_id)
    assert {:ok, %{user: "new"}} = OneTimeTokenStore.verify(store, new_id)
  end

  # -------------------------------------------------------
  # Edge cases
  # -------------------------------------------------------

  test "token with minimal TTL (1ms)", %{store: _store} do
    {:ok, short} =
      OneTimeTokenStore.start_link(
        clock: &Clock.now/0,
        default_ttl_ms: 1,
        cleanup_interval_ms: :infinity
      )

    {:ok, id} = OneTimeTokenStore.mint(short, %{flash: true})
    assert {:ok, _} = OneTimeTokenStore.verify(short, id)

    Clock.advance(2)
    assert {:error, :not_found} = OneTimeTokenStore.verify(short, id)
  end

  test "mint works with various payload types", %{store: store} do
    {:ok, id1} = OneTimeTokenStore.mint(store, "just a string")
    {:ok, id2} = OneTimeTokenStore.mint(store, [1, 2, 3])
    {:ok, id3} = OneTimeTokenStore.mint(store, {:tuple, :data})

    assert {:ok, "just a string"} = OneTimeTokenStore.redeem(store, id1)
    assert {:ok, [1, 2, 3]} = OneTimeTokenStore.redeem(store, id2)
    assert {:ok, {:tuple, :data}} = OneTimeTokenStore.redeem(store, id3)
  end

  test "double-redeem is rejected", %{store: store} do
    {:ok, id} = OneTimeTokenStore.mint(store, %{one_shot: true})

    assert {:ok, %{one_shot: true}} = OneTimeTokenStore.redeem(store, id)
    assert {:error, :not_found} = OneTimeTokenStore.redeem(store, id)
  end

  test "revoke then redeem is rejected", %{store: store} do
    {:ok, id} = OneTimeTokenStore.mint(store, %{code: "XYZ"})

    assert :ok = OneTimeTokenStore.revoke(store, id)
    assert {:error, :not_found} = OneTimeTokenStore.redeem(store, id)
  end

  test "server is reachable through its registered :name", %{store: _store} do
    name = :one_time_token_store_named_audit

    {:ok, _pid} =
      OneTimeTokenStore.start_link(
        name: name,
        clock: &Clock.now/0,
        default_ttl_ms: 1_000,
        cleanup_interval_ms: :infinity
      )

    {:ok, id} = OneTimeTokenStore.mint(name, %{via: :name})

    assert {:ok, %{via: :name}} = OneTimeTokenStore.verify(name, id)
    assert {:ok, %{via: :name}} = OneTimeTokenStore.redeem(name, id)
  end

  test "default TTL is one hour when :default_ttl_ms is not given", %{store: _store} do
    {:ok, hourly} =
      OneTimeTokenStore.start_link(
        clock: &Clock.now/0,
        cleanup_interval_ms: :infinity
      )

    {:ok, id} = OneTimeTokenStore.mint(hourly, %{scope: :default})

    Clock.advance(3_599_999)
    assert {:ok, %{scope: :default}} = OneTimeTokenStore.verify(hourly, id)

    Clock.advance(2)
    assert {:error, :not_found} = OneTimeTokenStore.verify(hourly, id)
  end

  # -------------------------------------------------------
  # The periodic cleanup is driven by an automatically scheduled timer
  # -------------------------------------------------------

  test "the periodic cleanup timer fires and re-arms automatically" do
    test_pid = self()

    # Every cleanup pass reads the clock. This probe records each such call;
    # no other API call is issued after startup, so each tick is an automatic
    # sweep.
    clock = fn ->
      send(test_pid, :cleanup_clock_tick)
      0
    end

    {:ok, _pid} =
      OneTimeTokenStore.start_link(default_ttl_ms: 1_000, clock: clock, cleanup_interval_ms: 25)

    # The first tick proves the startup timer fired; the second proves the pass
    # re-armed the next one, so the sweep repeats rather than running just once.
    # A scheduler that never arms Process.send_after would produce no ticks.
    assert_receive :cleanup_clock_tick, 1_000
    assert_receive :cleanup_clock_tick, 1_000
  end
end
```
