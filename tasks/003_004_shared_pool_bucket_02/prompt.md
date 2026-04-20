Implement the `handle_call/3` callback for the `{:acquire, name, key_cap, key_rate, tokens}` message.

First, determine the current time using the `clock` function stored in the state. Apply lazy refills to both levels BEFORE evaluating the drain: update the global pool by calling `refill_global/2`, and then update the per-key bucket by calling `get_and_refill_bucket/5`.

Next, evaluate the drain conditions in this strict order:
1. If the per-key bucket's free tokens are less than `tokens`: Calculate the deficit. Determine the `retry_after` time in milliseconds by dividing the deficit by the key refill rate (multiplied by 1000) and passing it to `ceil_positive/1`. Persist the refilled bucket in the state (without draining it) and return `{:reply, {:error, :key_empty, retry_after}, updated_state}`.
2. If the per-key bucket has enough, but the global pool's free tokens are less than `tokens`: Calculate the global deficit and its corresponding `retry_after` time using the global refill rate. Persist the refilled bucket in the state (without draining either level) and return `{:reply, {:error, :global_empty, retry_after}, updated_state}`.
3. If both levels have enough tokens: Atomically drain `tokens` from both the per-key bucket and the global pool. Persist both new balances in the state. Return `{:reply, {:ok, key_remaining, global_remaining}, updated_state}`, where both remaining values are the truncated integers (`trunc/1`) of their respective float balances.

```elixir
defmodule SharedPoolBucket do
  @moduledoc """
  A GenServer implementing two-level token-based rate limiting.

  Each call passes through two independent token buckets:

    1. A **per-key bucket**, whose capacity and refill rate are specified per
       call (like the original leaky bucket task).
    2. A **global pool** shared across all keys, whose capacity and refill
       rate are configured once at `start_link/1`.

  An acquire succeeds only when both levels have enough tokens.  If the
  per-key bucket is short, return `:key_empty`; if per-key has enough but
  the global pool is short, return `:global_empty`.  On rejection, **nothing
  is drained from either level** — both levels are returned to their pre-
  evaluation state (which, after the lazy refill, reflects the current time).

  Per-key state:

      %{free, capacity, refill_rate, last_update_at}

  Global state, stored at the top level (NOT in the buckets map):

      global_free :: float
      global_capacity :: pos_integer
      global_refill_rate :: float
      global_last_update_at :: integer

  ## Options

    * `:global_capacity`      – required, max tokens in the shared pool
    * `:global_refill_rate`   – required, shared-pool refill tokens/sec
    * `:name`                 – optional process registration
    * `:clock`                – `(-> integer())` current time in ms
    * `:cleanup_interval_ms`  – periodic sweep interval (default 60_000)

  """

  use GenServer

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    _ = Keyword.fetch!(opts, :global_capacity)
    _ = Keyword.fetch!(opts, :global_refill_rate)

    {name, opts} = Keyword.pop(opts, :name)

    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, server_opts)
  end

  @doc """
  Attempts to atomically drain `tokens` from both the per-key bucket and the
  shared global pool.

  Returns `{:ok, key_remaining, global_remaining}` on success, or
  `{:error, :key_empty | :global_empty, retry_after_ms}` on rejection.
  `:key_empty` takes precedence when both levels would fail.
  """
  @spec acquire(GenServer.server(), term(), pos_integer(), number(), pos_integer()) ::
          {:ok, non_neg_integer(), non_neg_integer()}
          | {:error, :key_empty | :global_empty, pos_integer()}
  def acquire(server, bucket_name, key_capacity, key_refill_rate, tokens \\ 1)
      when is_integer(key_capacity) and key_capacity > 0 and
           is_number(key_refill_rate) and key_refill_rate > 0 and
           is_integer(tokens) and tokens > 0 do
    GenServer.call(
      server,
      {:acquire, bucket_name, key_capacity, key_refill_rate * 1.0, tokens}
    )
  end

  @doc "Returns the current global pool balance (floor of float)."
  @spec global_level(GenServer.server()) :: {:ok, non_neg_integer()}
  def global_level(server), do: GenServer.call(server, :global_level)

  @doc """
  Returns the current per-key bucket balance (floor of float), or
  `{:ok, key_capacity}` if the bucket has never been seen.
  """
  @spec key_level(GenServer.server(), term(), pos_integer(), number()) ::
          {:ok, non_neg_integer()}
  def key_level(server, bucket_name, key_capacity, key_refill_rate)
      when is_integer(key_capacity) and key_capacity > 0 and
           is_number(key_refill_rate) and key_refill_rate > 0 do
    GenServer.call(
      server,
      {:key_level, bucket_name, key_capacity, key_refill_rate * 1.0}
    )
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @default_cleanup_interval_ms 60_000

  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    cleanup_interval = Keyword.get(opts, :cleanup_interval_ms, @default_cleanup_interval_ms)

    global_capacity = Keyword.fetch!(opts, :global_capacity)
    global_refill_rate = Keyword.fetch!(opts, :global_refill_rate) * 1.0

    now = clock.()
    schedule_cleanup(cleanup_interval)

    {:ok,
     %{
       buckets: %{},
       clock: clock,
       cleanup_interval_ms: cleanup_interval,
       # Global pool — lives at top level, not in buckets map.
       global_free: global_capacity * 1.0,
       global_capacity: global_capacity,
       global_refill_rate: global_refill_rate,
       global_last_update_at: now
     }}
  end

  @impl true
  def handle_call({:acquire, name, key_cap, key_rate, tokens}, _from, state) do
    # TODO
  end

  def handle_call(:global_level, _from, state) do
    state = refill_global(state, state.clock.())
    {:reply, {:ok, trunc(state.global_free)}, state}
  end

  def handle_call({:key_level, name, key_cap, key_rate}, _from, state) do
    case Map.fetch(state.buckets, name) do
      :error ->
        # Never seen — fresh buckets are full.
        {:reply, {:ok, key_cap}, state}

      {:ok, _} ->
        now = state.clock.()
        {bucket, state} = get_and_refill_bucket(state, name, key_cap, key_rate, now)
        new_buckets = Map.put(state.buckets, name, bucket)
        {:reply, {:ok, trunc(bucket.free)}, %{state | buckets: new_buckets}}
    end
  end

  @impl true
  def handle_info(:cleanup, state) do
    now = state.clock.()

    # Keep global refill up-to-date on cleanup too.
    state = refill_global(state, now)

    cleaned =
      Enum.reduce(state.buckets, %{}, fn {name, bucket}, acc ->
        elapsed = now - bucket.last_update_at
        projected = min(bucket.capacity * 1.0, bucket.free + elapsed * bucket.refill_rate / 1000)

        # Bucket indistinguishable from a fresh one — safe to drop.
        if projected >= bucket.capacity do
          acc
        else
          Map.put(acc, name, %{bucket | free: projected, last_update_at: now})
        end
      end)

    schedule_cleanup(state.cleanup_interval_ms)
    {:noreply, %{state | buckets: cleaned}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Per-level refill helpers
  # ---------------------------------------------------------------------------

  defp refill_global(state, now) do
    elapsed = now - state.global_last_update_at
    added = elapsed * state.global_refill_rate / 1000
    new_free = min(state.global_capacity * 1.0, state.global_free + added)
    %{state | global_free: new_free, global_last_update_at: now}
  end

  defp get_and_refill_bucket(state, name, key_cap, key_rate, now) do
    bucket =
      case Map.fetch(state.buckets, name) do
        {:ok, existing} ->
          # Allow capacity/rate to be updated mid-stream.
          %{existing | capacity: key_cap, refill_rate: key_rate}

        :error ->
          %{
            free: key_cap * 1.0,
            capacity: key_cap,
            refill_rate: key_rate,
            last_update_at: now
          }
      end

    elapsed = now - bucket.last_update_at
    added = elapsed * bucket.refill_rate / 1000
    new_free = min(bucket.capacity * 1.0, bucket.free + added)

    {%{bucket | free: new_free, last_update_at: now}, state}
  end

  # ---------------------------------------------------------------------------
  # Misc
  # ---------------------------------------------------------------------------

  defp ceil_positive(x) when is_number(x) do
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