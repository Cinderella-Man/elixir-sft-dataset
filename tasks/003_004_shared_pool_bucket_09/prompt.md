# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `ceil_positive` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

Write me an Elixir GenServer module called `SharedPoolBucket` that implements **two-level** token-based rate limiting — each named bucket has its own capacity and refill rate, but all acquires also draw against a shared global pool that constrains the whole server.

The motivation: in multi-tenant systems (SaaS APIs, shared compute clusters), each tenant deserves their own fair allocation (so one tenant can't monopolize), but the infrastructure also has a hard system-wide throughput ceiling (database connections, bandwidth, etc.). A request succeeds only when *both* the tenant's per-key bucket AND the global pool have enough tokens. This is different from a hierarchical limiter (which has multiple tiers per individual key) — here the second level spans across all keys.

I need these functions in the public API:

- `SharedPoolBucket.start_link(opts)` to start the process. The global pool is configured at start time:
  - `:global_capacity` — pool maximum (required, positive integer)
  - `:global_refill_rate` — pool refill rate in tokens/sec (required, positive number)
  - `:clock` — zero-arity function returning current time in ms (default `fn -> System.monotonic_time(:millisecond) end`)
  - `:name` — optional process registration
  - `:cleanup_interval_ms` — periodic sweep interval (default 60_000)

- `SharedPoolBucket.acquire(server, bucket_name, key_capacity, key_refill_rate, tokens \\ 1)` — attempts to drain `tokens` from the named bucket AND from the global pool atomically. Both must have sufficient tokens or the request is rejected and **nothing is drained from either level**. Per-key buckets start full at `key_capacity` when first seen; the global pool starts full at `global_capacity` when the server starts.

  Both levels use the standard lazy-refill formula: `new_tokens = min(capacity, old_tokens + elapsed_ms * refill_rate / 1000)`. Apply the refill to both levels before evaluating the drain.

  Return values:
  - `{:ok, key_remaining, global_remaining}` on success, both as integer floors of the post-drain float balances.
  - `{:error, :key_empty, retry_after_ms}` if the per-key bucket doesn't have enough tokens (retry_after reflects how long until the per-key bucket has enough).
  - `{:error, :global_empty, retry_after_ms}` if the per-key bucket would have admitted but the global pool is insufficient (retry_after reflects the global shortage).
  - If both levels are short, return the **per-key** error first (a caller whose own tier is depleted shouldn't be given the false impression that the global pool is their blocker). This ordering matters — it's explicit in the semantics.

  `acquire/5` and `key_level/4` must validate their arguments with function
  guards: a non-positive `key_capacity`, non-positive `key_refill_rate`, or
  non-positive `tokens` matches no clause and raises `FunctionClauseError` —
  an invalid call must never drain tokens or create a bucket. A `retry_after_ms`
  is always at least 1 (a sub-millisecond shortage still reports 1 ms) and is
  rounded UP from the exact `deficit * 1000 / refill_rate` computation.

- `SharedPoolBucket.global_level(server)` — returns `{:ok, integer_remaining}` with the floor of the current global pool balance after applying the lazy refill.

- `SharedPoolBucket.key_level(server, bucket_name, key_capacity, key_refill_rate)` — returns `{:ok, integer_remaining}` for the specified per-key bucket (refilled lazily) or `{:ok, key_capacity}` if the bucket has never been seen. The capacity/refill arguments are needed because they're not stored at bucket-creation time — the bucket is defined per-acquire. Querying `key_level` never creates or mutates a bucket: for an unseen name it just reports `{:ok, key_capacity}` without recording anything, so a repeated query for that same name with a different `key_capacity` still reports a fresh, full bucket at the new capacity.

Per-bucket state (per key) must track the current token count (float), the last access timestamp, the last-known capacity, and the last-known refill rate. The global pool tracks its own token count (float) and last-refill timestamp in the top-level GenServer state (NOT in the buckets map).

Periodic cleanup via `Process.send_after` every `:cleanup_interval_ms` milliseconds. The sweep drops any per-key bucket whose projected free balance has refilled back to capacity (indistinguishable from a fresh bucket). The global pool is never dropped. Use the injectable clock, not wall time.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.

## Additional interface contract

- The `:cleanup_interval_ms` option may also be `:infinity`, in which case the periodic
  timer is never scheduled — nothing runs automatically.

- Sending the server process a bare `:cleanup` message performs one cleanup
  pass immediately — the same work the periodic timer performs.

## The module with `ceil_positive` missing

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
    # TODO
  end

  defp schedule_cleanup(:infinity), do: :ok

  defp schedule_cleanup(interval_ms) when is_integer(interval_ms) do
    Process.send_after(self(), :cleanup, interval_ms)
  end
end
```

Give me only the complete implementation of `ceil_positive` (including any
`@doc`/`@spec`/`@impl` lines that belong directly above it) — the
function alone, not the whole module.
