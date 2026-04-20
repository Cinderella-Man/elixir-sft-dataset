Implement the `handle_info/2` callback for the `:cleanup` message.

First, fetch the current time using the `clock` function from the state. Keep the global pool up-to-date by passing the state and the current time through `refill_global/2`.

Next, perform a sweep of `state.buckets` using `Enum.reduce/3`. For each bucket, calculate the elapsed time since its `last_update_at` and compute its projected free balance (current free balance plus elapsed time multiplied by the refill rate divided by 1000, capped at its float capacity). 

- If the projected balance is greater than or equal to the bucket's capacity, the bucket is indistinguishable from a fresh one and should be safely dropped (do not include it in the accumulator).
- Otherwise, keep the bucket in the map, updating its `free` balance to the projected amount and its `last_update_at` to the current time.

After the reduction, call `schedule_cleanup/1` with `state.cleanup_interval_ms` to enqueue the next sweep. Finally, return `{:noreply, updated_state}` where the state contains the cleaned-up map of buckets.

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
    now = state.clock.()

    # Apply lazy refill to both levels BEFORE evaluating the drain.
    state = refill_global(state, now)
    {bucket, state} = get_and_refill_bucket(state, name, key_cap, key_rate, now)

    cond do
      bucket.free < tokens ->
        # Per-key is the blocker — signal :key_empty even if global is also short.
        deficit = tokens - bucket.free
        retry_after = ceil_positive(deficit * 1000 / key_rate)

        # Persist the refilled bucket state (no drain) so the refill clock
        # is up to date next time.
        new_buckets = Map.put(state.buckets, name, bucket)
        {:reply, {:error, :key_empty, retry_after}, %{state | buckets: new_buckets}}

      state.global_free < tokens ->
        # Per-key would have permitted, global is the blocker.
        deficit = tokens - state.global_free
        retry_after = ceil_positive(deficit * 1000 / state.global_refill_rate)

        new_buckets = Map.put(state.buckets, name, bucket)
        {:reply, {:error, :global_empty, retry_after}, %{state | buckets: new_buckets}}

      true ->
        # Drain both levels atomically.
        new_bucket = %{bucket | free: bucket.free - tokens}
        new_buckets = Map.put(state.buckets, name, new_bucket)
        new_global = state.global_free - tokens

        {:reply, {:ok, trunc(new_bucket.free), trunc(new_global)},
         %{state | buckets: new_buckets, global_free: new_global}}
    end
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
    # TODO
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