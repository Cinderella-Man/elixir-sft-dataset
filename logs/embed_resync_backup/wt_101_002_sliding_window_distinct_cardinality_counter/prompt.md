# Write tests for this module

Below is a completed Elixir module and the original specification it was built to
satisfy. Write a comprehensive ExUnit test harness that verifies a correct
implementation of this module.

Requirements for the harness:
- Define a module `<Module>Test` that does `use ExUnit.Case, async: false`.
- Do NOT call `ExUnit.start()` — the evaluator starts ExUnit itself.
- Make it self-contained: any fakes, clock Agents, or helpers are defined inline.
- Cover the full public API and the important edge cases described in the spec.
- It must compile with ZERO warnings (prefix unused variables with `_`; match float
  zero as `+0.0`/`-0.0`).
- Give me the complete harness in a single file.

## Original specification

Write me an Elixir GenServer module called `SlidingUniqueCounter` that tracks the
number of **distinct members** seen for a key within a sliding time window, using
a sub-bucket strategy.

Unlike a plain event counter, this counter answers "how many *unique* things did
we see", not "how many events happened". Adding the same member many times inside
the window still counts as one.

I need these functions in the public API:
- `SlidingUniqueCounter.start_link(opts)` to start the process. Returns
  `{:ok, pid}` on success, like a standard GenServer start. It should accept:
  - `:clock` — a zero-arity function returning the current time in milliseconds.
    Defaults to `fn -> System.monotonic_time(:millisecond) end`.
  - `:bucket_ms` — the width of each internal sub-bucket in milliseconds.
    Defaults to `1_000` (1 second).
  - `:name` — optional process registration name. When given, the whole API must
    be usable by passing that name in place of the pid.
  - `:cleanup_interval_ms` — how often to run the periodic cleanup.
    Defaults to `60_000`. Pass `:infinity` to disable.
  - `:max_window_ms` — the retention horizon used by cleanup: buckets whose
    start time is older than `now - max_window_ms` are removed. Defaults to
    `3_600_000` (1 hour).
- `SlidingUniqueCounter.add(server, key, member)` — records that `member` was
  observed for the given `key` at the current clock time. Returns `:ok`.
- `SlidingUniqueCounter.distinct_count(server, key, window_ms)` — returns the
  number of **distinct** members observed for `key` that fall within the last
  `window_ms` milliseconds relative to the current clock time. Members observed
  only outside that window must not be counted. Returns `0` for a key that has
  never been added.
- `SlidingUniqueCounter.tracked_key_count(server)` — returns how many keys
  currently hold any tracked data at all (0 once cleanup has removed
  everything).

Counting semantics:
- Adding the same member more than once (whether in the same instant or spread
  across time) counts that member exactly **once** within a window.
- A member that was observed in more than one in-window bucket is still counted
  once — the answer is the size of the union of all in-window buckets.
- A member counts if it was observed at least once inside the window, even if it
  was also observed outside the window.

Internal design requirements:
- Divide time into fixed-width sub-buckets of `:bucket_ms` each. Every observation
  is placed into the bucket whose index is `div(timestamp, bucket_ms)`. Each
  bucket stores the **set** of distinct members observed inside it.
- When answering `distinct_count/3`, only include buckets whose start time is at
  or after `now - window_ms`. A bucket at index `b` starts at `b * bucket_ms`.
  Discard (do not count) any bucket whose start time falls before
  `now - window_ms`. Concretely, a member counts when the START of its bucket
  (`b * bucket_ms`) satisfies `b * bucket_ms >= now - window_ms` — bucket
  granularity, not per-observation timestamps, decides inclusion.
- Different keys must be tracked independently — adding to "page:home" must not
  affect "page:about".
- Memory must not leak: run a periodic cleanup (via `Process.send_after`) that
  removes all buckets — and whole keys — that have fallen outside the
  `:max_window_ms` retention horizon. A bucket is kept only while its start time
  satisfies `b * bucket_ms >= now - max_window_ms`; older buckets are dropped, and
  a key with no remaining buckets is dropped entirely. Cleanup must keep the live
  buckets of a key even when it drops that key's expired ones. The periodic
  cleanup must re-schedule itself so data that expires later is still reclaimed
  (unless `:cleanup_interval_ms` is `:infinity`, in which case no periodic cleanup
  ever runs). Also handle a `:cleanup` message sent directly to the process so
  tests can trigger cleanup synchronously. After cleanup, `tracked_key_count/1`
  must report `0` when all data has expired.

Give me the complete module in a single file. Use only the OTP standard library,
no external dependencies.

## Module under test

```elixir
defmodule SlidingUniqueCounter do
  @moduledoc """
  A GenServer that tracks the number of **distinct members** seen for a key
  within a sliding time window, using a fixed-width sub-bucket strategy.

  Unlike a plain event counter, this counter answers "how many *unique* things
  did we see", not "how many events happened". Adding the same member many
  times inside the window still counts that member exactly once.

  ## Design

  Time is divided into fixed-width sub-buckets of `:bucket_ms` milliseconds.
  Every observation is placed into the bucket whose index is
  `div(timestamp, bucket_ms)`. Each bucket stores the `MapSet` of distinct
  members observed inside it. A `distinct_count/3` query unions the member sets
  of every in-window bucket and returns the size of that union, so a member
  observed in several in-window buckets is still counted once.

  Different keys are tracked independently. A periodic cleanup removes buckets
  (and whole keys) that have fallen outside a maximum retention window so that
  memory does not grow without bound.
  """

  use GenServer

  @default_bucket_ms 1_000
  @default_cleanup_interval_ms 60_000
  @default_max_window_ms 3_600_000

  @type key :: term()
  @type member :: term()
  @type server :: GenServer.server()

  @typep state :: %{
           clock: (-> integer()),
           bucket_ms: pos_integer(),
           cleanup_interval_ms: pos_integer() | :infinity,
           max_window_ms: pos_integer(),
           keys: %{optional(key()) => %{optional(integer()) => MapSet.t()}}
         }

  @doc """
  Starts the counter process.

  ## Options

    * `:clock` — a zero-arity function returning the current time in
      milliseconds. Defaults to `fn -> System.monotonic_time(:millisecond) end`.
    * `:bucket_ms` — the width of each internal sub-bucket in milliseconds.
      Defaults to `1_000`.
    * `:name` — optional process registration name.
    * `:cleanup_interval_ms` — how often to run the periodic cleanup.
      Defaults to `60_000`. Pass `:infinity` to disable.
    * `:max_window_ms` — buckets older than this relative to the current clock
      time are discarded during cleanup. Defaults to `3_600_000`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @doc """
  Records that `member` was observed for `key` at the current clock time.

  Always returns `:ok`.
  """
  @spec add(server(), key(), member()) :: :ok
  def add(server, key, member) do
    GenServer.call(server, {:add, key, member})
  end

  @doc """
  Returns the number of **distinct** members observed for `key` that fall
  within the last `window_ms` milliseconds relative to the current clock time.

  Members observed only outside that window are not counted. A member observed
  in more than one in-window bucket is counted once (the union of all in-window
  buckets).
  """
  @spec distinct_count(server(), key(), non_neg_integer()) :: non_neg_integer()
  def distinct_count(server, key, window_ms) do
    GenServer.call(server, {:distinct_count, key, window_ms})
  end

  @doc """
  Returns the number of keys currently retained by the counter.

  A key is retained only while it still holds at least one bucket. Once cleanup
  discards a key's last remaining bucket, the key is dropped entirely and no
  longer counted here. This exposes retained storage through the public API so
  callers can assert that memory does not leak.
  """
  @spec tracked_key_count(server()) :: non_neg_integer()
  def tracked_key_count(server) do
    GenServer.call(server, :tracked_key_count)
  end

  @impl true
  @spec init(keyword()) :: {:ok, state()}
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    bucket_ms = Keyword.get(opts, :bucket_ms, @default_bucket_ms)
    cleanup_interval_ms = Keyword.get(opts, :cleanup_interval_ms, @default_cleanup_interval_ms)
    max_window_ms = Keyword.get(opts, :max_window_ms, @default_max_window_ms)

    state = %{
      clock: clock,
      bucket_ms: bucket_ms,
      cleanup_interval_ms: cleanup_interval_ms,
      max_window_ms: max_window_ms,
      keys: %{}
    }

    schedule_cleanup(cleanup_interval_ms)
    {:ok, state}
  end

  @impl true
  def handle_call({:add, key, member}, _from, state) do
    now = state.clock.()
    index = div(now, state.bucket_ms)

    buckets = Map.get(state.keys, key, %{})
    set = Map.get(buckets, index, MapSet.new())
    buckets = Map.put(buckets, index, MapSet.put(set, member))
    keys = Map.put(state.keys, key, buckets)

    {:reply, :ok, %{state | keys: keys}}
  end

  def handle_call({:distinct_count, key, window_ms}, _from, state) do
    now = state.clock.()
    threshold = now - window_ms
    buckets = Map.get(state.keys, key, %{})

    union =
      Enum.reduce(buckets, MapSet.new(), fn {index, set}, acc ->
        if index * state.bucket_ms >= threshold do
          MapSet.union(acc, set)
        else
          acc
        end
      end)

    {:reply, MapSet.size(union), state}
  end

  def handle_call(:tracked_key_count, _from, state) do
    {:reply, map_size(state.keys), state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    state = purge_expired(state)
    schedule_cleanup(state.cleanup_interval_ms)
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @spec schedule_cleanup(pos_integer() | :infinity) :: :ok
  defp schedule_cleanup(:infinity), do: :ok

  defp schedule_cleanup(interval_ms) when is_integer(interval_ms) do
    Process.send_after(self(), :cleanup, interval_ms)
    :ok
  end

  @spec purge_expired(state()) :: state()
  defp purge_expired(state) do
    now = state.clock.()
    threshold = now - state.max_window_ms

    keys =
      Enum.reduce(state.keys, %{}, fn {key, buckets}, acc ->
        kept =
          Enum.reduce(buckets, %{}, fn {index, set}, inner ->
            if index * state.bucket_ms >= threshold do
              Map.put(inner, index, set)
            else
              inner
            end
          end)

        if map_size(kept) == 0, do: acc, else: Map.put(acc, key, kept)
      end)

    %{state | keys: keys}
  end
end
```
