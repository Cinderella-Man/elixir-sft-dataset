# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule HierarchicalLimiter do
  @moduledoc """
  A GenServer that enforces multiple simultaneous sliding-window rate limits
  per key.  A request is accepted only when it passes every configured tier.

  Each key is backed by a single sorted list of request timestamps (newest
  first).  For each incoming `check/3` call, every tier counts how many
  recorded timestamps fall within its own window.  If any tier's count has
  already reached its limit, the request is rejected and the tightest
  offending tier is reported — "tightest" meaning the tier whose oldest
  in-window timestamp is farthest from expiring (longest retry_after).

  Rejected requests do **not** record a new timestamp, so they don't consume
  budget under any tier.

  Timestamps older than the widest tier window are dropped lazily on every
  check and aggressively during the periodic cleanup sweep, bounding the
  per-key state.

  ## Options

    * `:name`                 – process registration name (optional)
    * `:clock`                – zero-arity function returning current time in ms
                                (default: `fn -> System.monotonic_time(:millisecond) end`)
    * `:cleanup_interval_ms`  – how often the periodic sweep runs in ms (default: 60_000)

  ## Examples

      iex> {:ok, pid} = HierarchicalLimiter.start_link([])
      iex> tiers = [{:per_second, 10, 1_000}, {:per_minute, 100, 60_000}]
      iex> {:ok, %{per_second: 9, per_minute: 99}} = HierarchicalLimiter.check(pid, "user:1", tiers)

  """

  use GenServer

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts the HierarchicalLimiter process and links it to the caller.

  ## Options

    * `:name`                 – optional registered name
    * `:clock`                – `(-> integer())` returning now in milliseconds
    * `:cleanup_interval_ms`  – sweep interval (default `60_000`)

  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)

    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, server_opts)
  end

  @doc """
  Checks whether a request for `key` passes every tier in `tiers`.

  `tiers` is a list of `{tier_name, max_requests, window_ms}` tuples.  A
  request is accepted only when every tier has capacity.  On success, returns
  `{:ok, remaining_by_tier}` — a map from tier name to the remaining
  allowance under that tier after accepting the request.

  On failure, returns `{:error, :rate_limited, tier_name, retry_after_ms}`
  identifying the tier that kept the request out for the longest and the wait
  (in milliseconds) until that tier's oldest in-window timestamp expires.
  """
  @spec check(GenServer.server(), term(), [{atom(), pos_integer(), pos_integer()}, ...]) ::
          {:ok, %{atom() => non_neg_integer()}}
          | {:error, :rate_limited, atom(), non_neg_integer()}
  def check(server, key, [_ | _] = tiers) do
    :ok = validate_tiers!(tiers)
    GenServer.call(server, {:check, key, tiers})
  end

  defp validate_tiers!(tiers) do
    Enum.each(tiers, fn
      {name, max, window}
      when is_atom(name) and is_integer(max) and max > 0 and
             is_integer(window) and window > 0 ->
        :ok

      bad ->
        raise ArgumentError,
              "invalid tier #{inspect(bad)} — expected {atom, pos_integer, pos_integer}"
    end)

    :ok
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @default_cleanup_interval_ms 60_000

  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    cleanup_interval = Keyword.get(opts, :cleanup_interval_ms, @default_cleanup_interval_ms)

    schedule_cleanup(cleanup_interval)

    {:ok,
     %{
       # %{key => {[timestamp_newest_first], widest_window_seen_ms}}
       keys: %{},
       clock: clock,
       cleanup_interval_ms: cleanup_interval
     }}
  end

  @impl true
  def handle_call({:check, key, tiers}, _from, state) do
    now = state.clock.()
    widest_window = tiers |> Enum.map(fn {_n, _m, w} -> w end) |> Enum.max()

    # Fetch and lazily prune to the widest tier window.
    {timestamps, _old_widest} = Map.get(state.keys, key, {[], widest_window})
    active = Enum.take_while(timestamps, fn ts -> ts > now - widest_window end)

    # Evaluate every tier against the pruned list.
    case evaluate_tiers(tiers, active, now) do
      {:ok, remaining_by_tier} ->
        # All tiers pass — record this request's timestamp at the front.
        new_entry = {[now | active], widest_window}
        {:reply, {:ok, remaining_by_tier}, %{state | keys: Map.put(state.keys, key, new_entry)}}

      {:rejected, tier_name, retry_after} ->
        # Persist the pruned list even on failure so we don't re-prune next time.
        new_entry = {active, widest_window}

        {:reply, {:error, :rate_limited, tier_name, retry_after},
         %{state | keys: Map.put(state.keys, key, new_entry)}}
    end
  end

  @impl true
  def handle_info(:cleanup, state) do
    now = state.clock.()

    cleaned =
      Enum.reduce(state.keys, %{}, fn {key, {timestamps, widest}}, acc ->
        cutoff = now - widest
        active = Enum.take_while(timestamps, fn ts -> ts > cutoff end)

        if active == [] do
          acc
        else
          Map.put(acc, key, {active, widest})
        end
      end)

    schedule_cleanup(state.cleanup_interval_ms)

    {:noreply, %{state | keys: cleaned}}
  end

  # Catch-all so unexpected messages don't crash the process.
  def handle_info(_msg, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Tier evaluation
  # ---------------------------------------------------------------------------

  # For each tier: count the in-window timestamps.  If any tier is at its
  # limit, collect its retry_after and pick the tightest (longest wait).
  # Otherwise, build the remaining_by_tier map.
  defp evaluate_tiers(tiers, active, now) do
    results =
      Enum.map(tiers, fn {name, max_requests, window_ms} ->
        window_start = now - window_ms
        in_window = Enum.take_while(active, fn ts -> ts > window_start end)
        count = length(in_window)

        if count < max_requests do
          # `count` already-recorded requests; after accepting the new one,
          # `count + 1` will exist, leaving `max_requests - count - 1` headroom.
          {:pass, name, max_requests - count - 1}
        else
          # Tier saturated.  The oldest in-window timestamp is the last one
          # in the truncated list (timestamps are newest-first).  Wait until
          # it exits the window.
          oldest = List.last(in_window)
          retry_after = max(oldest + window_ms - now, 1)
          {:fail, name, retry_after}
        end
      end)

    case Enum.filter(results, &match?({:fail, _, _}, &1)) do
      [] ->
        remaining =
          Enum.reduce(results, %{}, fn {:pass, name, r}, acc -> Map.put(acc, name, r) end)

        {:ok, remaining}

      failures ->
        # Tightest = longest retry_after (the one the caller actually has to wait on).
        {:fail, name, retry_after} =
          Enum.max_by(failures, fn {:fail, _n, retry} -> retry end)

        {:rejected, name, retry_after}
    end
  end

  # ---------------------------------------------------------------------------
  # Internal helpers
  # ---------------------------------------------------------------------------

  defp schedule_cleanup(:infinity), do: :ok

  defp schedule_cleanup(interval_ms) when is_integer(interval_ms) do
    Process.send_after(self(), :cleanup, interval_ms)
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule HierarchicalLimiterTest do
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
    # Start fresh clock at time 0 for each test
    start_supervised!({Clock, 0})

    {:ok, pid} =
      HierarchicalLimiter.start_link(
        clock: &Clock.now/0,
        # disable auto-cleanup in tests
        cleanup_interval_ms: :infinity
      )

    %{hl: pid}
  end

  # -------------------------------------------------------
  # Single-tier behaviour (should match sliding window)
  # -------------------------------------------------------

  test "with a single tier, behaves like a sliding window limiter", %{hl: hl} do
    tiers = [{:per_sec, 3, 1_000}]

    assert {:ok, %{per_sec: 2}} = HierarchicalLimiter.check(hl, "k", tiers)
    assert {:ok, %{per_sec: 1}} = HierarchicalLimiter.check(hl, "k", tiers)
    assert {:ok, %{per_sec: 0}} = HierarchicalLimiter.check(hl, "k", tiers)
    assert {:error, :rate_limited, :per_sec, _} = HierarchicalLimiter.check(hl, "k", tiers)
  end

  # -------------------------------------------------------
  # Multi-tier: all must pass
  # -------------------------------------------------------

  test "request is allowed only when every tier has capacity", %{hl: hl} do
    tiers = [{:per_sec, 5, 1_000}, {:per_min, 10, 60_000}]

    # Burn through the per_sec tier (5 requests at t=0).
    for _ <- 1..5, do: HierarchicalLimiter.check(hl, "k", tiers)

    # 6th request is rejected by per_sec even though per_min still has headroom.
    assert {:error, :rate_limited, :per_sec, _} = HierarchicalLimiter.check(hl, "k", tiers)

    # Advance to t=1001, per_sec clears, per_min still holds 5 of 10.
    Clock.advance(1_001)
    assert {:ok, %{per_sec: 4, per_min: 4}} = HierarchicalLimiter.check(hl, "k", tiers)
  end

  test "tighter outer tier can reject even when inner tier has capacity", %{hl: hl} do
    # 10/sec AND 15/min — the minute cap is the binding constraint across bursts.
    tiers = [{:per_sec, 10, 1_000}, {:per_min, 15, 60_000}]

    # 10 requests in the first second
    for _ <- 1..10, do: HierarchicalLimiter.check(hl, "k", tiers)

    # Advance 1.5 seconds: per_sec is clear, per_min has 10 and allows 5 more.
    Clock.advance(1_500)
    for _ <- 1..5, do: HierarchicalLimiter.check(hl, "k", tiers)

    # 16th request: per_sec has headroom but per_min is full → rejected by per_min.
    assert {:error, :rate_limited, :per_min, _} = HierarchicalLimiter.check(hl, "k", tiers)
  end

  test "rejected requests do not consume budget on any tier", %{hl: hl} do
    tiers = [{:per_sec, 2, 1_000}, {:per_min, 10, 60_000}]

    assert {:ok, %{per_sec: 1, per_min: 9}} = HierarchicalLimiter.check(hl, "k", tiers)
    assert {:ok, %{per_sec: 0, per_min: 8}} = HierarchicalLimiter.check(hl, "k", tiers)

    # Blast a bunch of rejections against per_sec.
    for _ <- 1..10 do
      assert {:error, :rate_limited, :per_sec, _} = HierarchicalLimiter.check(hl, "k", tiers)
    end

    # Advance past the per_sec window. per_min must show only 2 consumed,
    # not 12 — rejections shouldn't count.
    Clock.advance(1_001)
    assert {:ok, %{per_min: 7}} = HierarchicalLimiter.check(hl, "k", tiers)
  end

  # -------------------------------------------------------
  # Tightest-tier reporting
  # -------------------------------------------------------

  test "reports the tier with the longest retry_after when multiple fail", %{hl: hl} do
    # Both tiers will saturate simultaneously at t=0.
    tiers = [{:per_sec, 3, 1_000}, {:per_min, 3, 60_000}]

    for _ <- 1..3, do: HierarchicalLimiter.check(hl, "k", tiers)

    # Both tiers are at their limit. per_min's retry_after is ~60_000;
    # per_sec's is ~1_000. The caller has to wait on per_min.
    assert {:error, :rate_limited, :per_min, retry_after} =
             HierarchicalLimiter.check(hl, "k", tiers)

    assert retry_after > 1_000
    assert retry_after <= 60_000
  end

  # -------------------------------------------------------
  # Key independence
  # -------------------------------------------------------

  test "different keys have independent budgets across all tiers", %{hl: hl} do
    # TODO
  end

  # -------------------------------------------------------
  # retry_after accuracy per tier
  # -------------------------------------------------------

  test "retry_after tracks the blocking tier's oldest-entry expiry", %{hl: hl} do
    tiers = [{:per_sec, 1, 1_000}]

    HierarchicalLimiter.check(hl, "k", tiers)
    Clock.advance(300)

    assert {:error, :rate_limited, :per_sec, retry_after} =
             HierarchicalLimiter.check(hl, "k", tiers)

    # Oldest (and only) entry is at t=0, expires at t=1000. We're at t=300.
    assert retry_after >= 600 and retry_after <= 800
  end

  # -------------------------------------------------------
  # Three-tier stack: the motivating real-world case
  # -------------------------------------------------------

  test "three-tier stack admits a sustainable request rate", %{hl: hl} do
    tiers = [
      {:per_sec, 10, 1_000},
      {:per_min, 100, 60_000},
      {:per_hour, 1_000, 3_600_000}
    ]

    # 10 requests at t=0 — saturates per_sec.
    for _ <- 1..10, do: HierarchicalLimiter.check(hl, "k", tiers)
    assert {:error, :rate_limited, :per_sec, _} = HierarchicalLimiter.check(hl, "k", tiers)

    # Advance a second, fire 10 more. Still under per_min (20/100) and per_hour (20/1000).
    Clock.advance(1_001)

    for i <- 1..10 do
      assert {:ok, remaining} = HierarchicalLimiter.check(hl, "k", tiers)
      assert remaining.per_sec == 10 - i
    end
  end

  # -------------------------------------------------------
  # Cleanup (memory leak prevention)
  # -------------------------------------------------------

  test "expired entries are pruned and empty keys dropped", %{hl: hl} do
    tiers = [{:per_sec, 1, 100}]

    for i <- 1..100 do
      HierarchicalLimiter.check(hl, "key:#{i}", tiers)
    end

    # Advance past the widest window
    Clock.advance(200)

    send(hl, :cleanup)
    :sys.get_state(hl)

    state = :sys.get_state(hl)
    assert map_size(state.keys) == 0

    # New requests work fresh
    assert {:ok, %{per_sec: 0}} = HierarchicalLimiter.check(hl, "key:1", tiers)
  end
end
```
