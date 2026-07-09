# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule GcraLimiter do
  @moduledoc """
  A GenServer that implements rate limiting using the Generic Cell Rate
  Algorithm (GCRA).

  GCRA tracks a single scalar per bucket — the **Theoretical Arrival Time**
  (TAT), which represents the earliest wall-clock time at which the next
  request would be admitted if no burst were allowed.  Admitting a request
  pushes the TAT forward by one emission interval per token consumed; bursts
  are permitted by admitting requests up to `delay_variation_tolerance`
  milliseconds *before* the current TAT.

  This is mathematically equivalent to a token bucket but uses a completely
  different representation — a single float per bucket instead of
  `{tokens, last_refill_at}`.

  ## Options

    * `:name`                 – process registration name (optional)
    * `:clock`                – zero-arity function returning current time in ms
                                (default: `fn -> System.monotonic_time(:millisecond) end`)
    * `:cleanup_interval_ms`  – periodic sweep interval (default 60_000)
    * `:cleanup_idle_ms`      – drop buckets whose TAT is this far in the past
                                (default 300_000)

  ## Examples

      iex> {:ok, pid} = GcraLimiter.start_link([])
      iex> {:ok, 4} = GcraLimiter.acquire(pid, "user:1", 5.0, 5)
      iex> {:ok, 3} = GcraLimiter.acquire(pid, "user:1", 5.0, 5)

  """

  use GenServer

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)

    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, server_opts)
  end

  @doc """
  Attempts to admit a request of `tokens` units for `bucket_name`.

  Returns `{:ok, remaining}` when admitted, where `remaining` is the number
  of additional tokens that could still be immediately admitted before the
  burst budget runs out.

  Returns `{:error, :rate_exceeded, retry_after_ms}` when the request would
  exceed the allowed burst.  TAT is not mutated on rejection — back-to-back
  rejected calls do not starve the caller of future admits.
  """
  @spec acquire(GenServer.server(), term(), number(), pos_integer(), pos_integer()) ::
          {:ok, non_neg_integer()} | {:error, :rate_exceeded, pos_integer()}
  def acquire(server, bucket_name, rate_per_sec, burst_size, tokens \\ 1)
      when is_number(rate_per_sec) and rate_per_sec > 0 and
             is_integer(burst_size) and burst_size > 0 and
             is_integer(tokens) and tokens > 0 do
    GenServer.call(server, {:acquire, bucket_name, rate_per_sec, burst_size, tokens})
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @default_cleanup_interval_ms 60_000
  @default_cleanup_idle_ms 300_000

  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    cleanup_interval = Keyword.get(opts, :cleanup_interval_ms, @default_cleanup_interval_ms)
    cleanup_idle = Keyword.get(opts, :cleanup_idle_ms, @default_cleanup_idle_ms)

    schedule_cleanup(cleanup_interval)

    {:ok,
     %{
       # %{bucket_name => tat_ms (float)}
       buckets: %{},
       clock: clock,
       cleanup_interval_ms: cleanup_interval,
       cleanup_idle_ms: cleanup_idle
     }}
  end

  @impl true
  def handle_call({:acquire, bucket, rate_per_sec, burst, tokens}, _from, state) do
    now = state.clock.()

    # Derived constants.
    emission_interval = 1000 / rate_per_sec
    dvt = burst * emission_interval

    # Fresh bucket starts at TAT = now (full burst immediately available).
    tat = Map.get(state.buckets, bucket, now * 1.0)

    # Advance the TAT baseline if the bucket has been idle past it —
    # without this `max`, idle time would be credited beyond `burst`.
    new_tat = max(now, tat) + tokens * emission_interval
    earliest_admit = new_tat - dvt

    if earliest_admit <= now do
      # Accept.  The remaining burst headroom, expressed in tokens, is how
      # much slack we still have between (new_tat - now) and DVT.
      slack = dvt - (new_tat - now)
      remaining = max(trunc(slack / emission_interval), 0)

      {:reply, {:ok, remaining}, %{state | buckets: Map.put(state.buckets, bucket, new_tat)}}
    else
      # Reject.  Crucially, do NOT update TAT — repeated rejects must not
      # push the admit frontier further into the future.
      retry_after = ceil_positive(earliest_admit - now)
      {:reply, {:error, :rate_exceeded, retry_after}, state}
    end
  end

  @impl true
  def handle_info(:cleanup, state) do
    now = state.clock.()
    idle_threshold = state.cleanup_idle_ms

    cleaned =
      Enum.reduce(state.buckets, %{}, fn {bucket, tat}, acc ->
        # If TAT is far enough in the past that the bucket would behave
        # identically to a fresh one, drop it.
        if now - tat >= idle_threshold do
          acc
        else
          Map.put(acc, bucket, tat)
        end
      end)

    schedule_cleanup(state.cleanup_interval_ms)
    {:noreply, %{state | buckets: cleaned}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  # Ceiling that always returns a positive integer, suitable for retry_after.
  defp ceil_positive(x) do
    c = trunc(x)
    c = if c < x, do: c + 1, else: c
    max(c, 1)
  end

  defp schedule_cleanup(:infinity), do: :ok

  defp schedule_cleanup(interval_ms) when is_integer(interval_ms) do
    Process.send_after(self(), :cleanup, interval_ms)
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule GcraLimiterTest do
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
      GcraLimiter.start_link(
        clock: &Clock.now/0,
        cleanup_interval_ms: :infinity
      )

    %{gl: pid}
  end

  # -------------------------------------------------------
  # Fresh bucket admits the full burst immediately
  # -------------------------------------------------------

  test "a brand-new bucket admits the configured burst back-to-back", %{gl: gl} do
    # 5 req/sec, burst of 5 — should admit 5 instantly
    assert {:ok, 4} = GcraLimiter.acquire(gl, "k", 5.0, 5)
    assert {:ok, 3} = GcraLimiter.acquire(gl, "k", 5.0, 5)
    assert {:ok, 2} = GcraLimiter.acquire(gl, "k", 5.0, 5)
    assert {:ok, 1} = GcraLimiter.acquire(gl, "k", 5.0, 5)
    assert {:ok, 0} = GcraLimiter.acquire(gl, "k", 5.0, 5)
  end

  test "rejects once the burst is exhausted", %{gl: gl} do
    # TODO
  end

  # -------------------------------------------------------
  # Steady-state rate (after burst is consumed)
  # -------------------------------------------------------

  test "admits at the steady-state rate after burst is exhausted", %{gl: gl} do
    for _ <- 1..5, do: GcraLimiter.acquire(gl, "k", 5.0, 5)
    assert {:error, :rate_exceeded, _} = GcraLimiter.acquire(gl, "k", 5.0, 5)

    # After one emission interval (200ms), one more is admitted.
    Clock.advance(200)
    assert {:ok, 0} = GcraLimiter.acquire(gl, "k", 5.0, 5)
    assert {:error, :rate_exceeded, _} = GcraLimiter.acquire(gl, "k", 5.0, 5)

    # Two more intervals → two more admits.
    Clock.advance(400)
    assert {:ok, 1} = GcraLimiter.acquire(gl, "k", 5.0, 5)
    assert {:ok, 0} = GcraLimiter.acquire(gl, "k", 5.0, 5)
    assert {:error, :rate_exceeded, _} = GcraLimiter.acquire(gl, "k", 5.0, 5)
  end

  # -------------------------------------------------------
  # The max(now, tat) trap — idle buckets don't accrue unbounded credit
  # -------------------------------------------------------

  test "long idle does not credit the bucket beyond burst size", %{gl: gl} do
    # Consume a few, then idle for a very long time.
    for _ <- 1..3, do: GcraLimiter.acquire(gl, "k", 5.0, 5)
    Clock.advance(10_000_000)

    # We should admit exactly `burst` requests back-to-back — the million
    # milliseconds of idle time must not translate to a million-request burst.
    assert {:ok, 4} = GcraLimiter.acquire(gl, "k", 5.0, 5)
    assert {:ok, 3} = GcraLimiter.acquire(gl, "k", 5.0, 5)
    assert {:ok, 2} = GcraLimiter.acquire(gl, "k", 5.0, 5)
    assert {:ok, 1} = GcraLimiter.acquire(gl, "k", 5.0, 5)
    assert {:ok, 0} = GcraLimiter.acquire(gl, "k", 5.0, 5)
    assert {:error, :rate_exceeded, _} = GcraLimiter.acquire(gl, "k", 5.0, 5)
  end

  # -------------------------------------------------------
  # The "don't advance TAT on rejection" trap
  # -------------------------------------------------------

  test "repeated rejects do not push future admits further away", %{gl: gl} do
    # Burn through the burst at t=0
    for _ <- 1..5, do: GcraLimiter.acquire(gl, "k", 5.0, 5)

    # Spam rejections — TAT must not advance with each one
    for _ <- 1..50, do: GcraLimiter.acquire(gl, "k", 5.0, 5)

    # After exactly one emission interval (200ms), we must still be able to
    # admit one.  If the implementation naively updated TAT on every reject,
    # the admit frontier would be 50 emission intervals into the future.
    Clock.advance(200)
    assert {:ok, 0} = GcraLimiter.acquire(gl, "k", 5.0, 5)
  end

  # -------------------------------------------------------
  # Bucket independence
  # -------------------------------------------------------

  test "different buckets maintain independent TATs", %{gl: gl} do
    for _ <- 1..5, do: GcraLimiter.acquire(gl, "a", 5.0, 5)
    assert {:error, :rate_exceeded, _} = GcraLimiter.acquire(gl, "a", 5.0, 5)

    # Bucket "b" has not been touched
    assert {:ok, 4} = GcraLimiter.acquire(gl, "b", 5.0, 5)
    assert {:ok, 3} = GcraLimiter.acquire(gl, "b", 5.0, 5)
  end

  # -------------------------------------------------------
  # Multi-token acquires
  # -------------------------------------------------------

  test "consuming multiple tokens at once deducts all of them", %{gl: gl} do
    # Burst of 5; take 3 in one call
    assert {:ok, 2} = GcraLimiter.acquire(gl, "k", 5.0, 5, 3)

    # Only 2 single-token acquires left in the burst
    assert {:ok, 1} = GcraLimiter.acquire(gl, "k", 5.0, 5)
    assert {:ok, 0} = GcraLimiter.acquire(gl, "k", 5.0, 5)
    assert {:error, :rate_exceeded, _} = GcraLimiter.acquire(gl, "k", 5.0, 5)
  end

  test "multi-token acquire that exceeds burst is rejected", %{gl: gl} do
    # Burst of 5; asking for 6 at once must be rejected
    assert {:error, :rate_exceeded, _} = GcraLimiter.acquire(gl, "k", 5.0, 5, 6)

    # And rejection must not have mutated TAT — the full burst is still available
    assert {:ok, 4} = GcraLimiter.acquire(gl, "k", 5.0, 5)
  end

  # -------------------------------------------------------
  # retry_after accuracy
  # -------------------------------------------------------

  test "retry_after reports time until the earliest admit", %{gl: gl} do
    # Consume full burst at t=0
    for _ <- 1..5, do: GcraLimiter.acquire(gl, "k", 5.0, 5)

    # At t=0 the next admit is at t=200 (one emission interval)
    assert {:error, :rate_exceeded, retry_after} =
             GcraLimiter.acquire(gl, "k", 5.0, 5)

    assert retry_after >= 1 and retry_after <= 200

    # At t=100, retry_after should be ~100
    Clock.advance(100)

    assert {:error, :rate_exceeded, retry_after_2} =
             GcraLimiter.acquire(gl, "k", 5.0, 5)

    assert retry_after_2 >= 1 and retry_after_2 <= 100
  end

  # -------------------------------------------------------
  # Cleanup
  # -------------------------------------------------------

  test "idle buckets are dropped by cleanup" do
    # Removed the redundant `start_supervised!({Clock, 0})` here

    {:ok, pid} =
      GcraLimiter.start_link(
        clock: &Clock.now/0,
        cleanup_interval_ms: :infinity,
        cleanup_idle_ms: 1_000
      )

    # Touch 100 buckets
    for i <- 1..100, do: GcraLimiter.acquire(pid, "k:#{i}", 5.0, 5)

    # Advance well past cleanup_idle_ms
    Clock.advance(2_000)

    send(pid, :cleanup)
    :sys.get_state(pid)

    state = :sys.get_state(pid)
    assert map_size(state.buckets) == 0

    # Fresh bucket after cleanup behaves like new
    assert {:ok, 4} = GcraLimiter.acquire(pid, "k:1", 5.0, 5)
  end

  # -------------------------------------------------------
  # Fractional rates
  # -------------------------------------------------------

  test "works with fractional rates (e.g. 0.5 req/sec)", %{gl: gl} do
    # 0.5 req/sec → emission_interval = 2000ms, burst of 2
    assert {:ok, 1} = GcraLimiter.acquire(gl, "slow", 0.5, 2)
    assert {:ok, 0} = GcraLimiter.acquire(gl, "slow", 0.5, 2)
    assert {:error, :rate_exceeded, _} = GcraLimiter.acquire(gl, "slow", 0.5, 2)

    # After 2 seconds, one more is admitted
    Clock.advance(2_000)
    assert {:ok, 0} = GcraLimiter.acquire(gl, "slow", 0.5, 2)
  end
end
```
