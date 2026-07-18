# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `handle_info` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

Write me an Elixir GenServer module called `SlidingAlerter` that watches a
sliding-window event rate per key and reports an alarm state when the rate
crosses a configured threshold — a self-clearing threshold detector built on a
sub-bucket sliding window.

I need these functions in the public API:
- `SlidingAlerter.start_link(opts)` to start the process. It should accept:
  - `:clock` — a zero-arity function returning the current time in milliseconds.
    Defaults to `fn -> System.monotonic_time(:millisecond) end`.
  - `:bucket_ms` — the width of each internal sub-bucket in milliseconds.
    Defaults to `1_000` (1 second).
  - `:threshold` — the event count within the alerting window at or above which
    a key is considered to be in alarm. Defaults to `5`.
  - `:window_ms` — the sliding alerting window width in milliseconds. Defaults to
    `60_000`.
  - `:name` — optional process registration name.
  - `:cleanup_interval_ms` — how often to run the periodic cleanup.
    Defaults to `60_000`. Pass `:infinity` to disable.
- `SlidingAlerter.record(server, key)` — records one event for the given key at
  the current clock time, then returns the key's resulting status (`:ok` or
  `:alarm`).
- `SlidingAlerter.status(server, key)` — returns `:ok` or `:alarm` for the key
  based on the current clock time, without recording anything.
- `SlidingAlerter.count(server, key)` — returns the number of events recorded for
  the key that fall within the last `:window_ms` milliseconds relative to the
  current clock time.

Status and counting semantics:
- A key's status is `:alarm` when the number of events for that key within the
  last `:window_ms` milliseconds is greater than or equal to `:threshold`;
  otherwise the status is `:ok`.
- A key that has never been recorded has a count of `0` and status `:ok`.
- The alarm is self-clearing: as events slide out of the window, the count falls,
  and once it drops below `:threshold` the status returns to `:ok` with no
  explicit reset.
- Time is divided into fixed-width sub-buckets of `:bucket_ms` each; every event
  is placed into the bucket whose index is `div(timestamp, bucket_ms)`. When
  computing the count for the alerting window, include a bucket iff its start time
  `b * bucket_ms >= now - window_ms`.
- Different keys must be tracked independently — recording `"user:a"` must not
  affect `"user:b"`.

Internal design and cleanup requirements:
- The GenServer state must store per-key bucket counts under `state.keys`.
- Memory must not leak: run a periodic cleanup (via `Process.send_after`) that
  removes buckets — and whole keys — that start before `now - window_ms`. Also
  handle a `:cleanup` message sent directly to the process so tests can trigger
  cleanup synchronously. After cleanup, `state.keys` must be an empty map when
  all data has expired.

Give me the complete module in a single file. Use only the OTP standard library,
no external dependencies.

## The module with `handle_info` missing

```elixir
defmodule SlidingAlerter do
  @moduledoc """
  A GenServer that watches a sliding-window event rate per key and reports an
  alarm state when the rate crosses a configured threshold.

  `SlidingAlerter` is a self-clearing threshold detector built on a sub-bucket
  sliding window. Time is divided into fixed-width sub-buckets of `:bucket_ms`
  milliseconds each. Every recorded event is placed into the bucket whose index
  is `div(timestamp, bucket_ms)`. The alerting window spans the most recent
  `:window_ms` milliseconds: a bucket is included in the window's count iff its
  start time `b * bucket_ms` is `>= now - window_ms`.

  A key is in the `:alarm` state when the number of events for that key within
  the window is greater than or equal to `:threshold`; otherwise it is `:ok`.
  The alarm is self-clearing — as events slide out of the window the count
  falls, and once it drops below `:threshold` the status returns to `:ok`
  without any explicit reset.

  A periodic cleanup (scheduled with `Process.send_after/3`) removes buckets —
  and whole keys — whose start time is before `now - window_ms`, so memory does
  not grow without bound.
  """

  use GenServer

  @type key :: term()
  @type status :: :ok | :alarm

  @default_bucket_ms 1_000
  @default_threshold 5
  @default_window_ms 60_000
  @default_cleanup_interval_ms 60_000

  # Public API

  @doc """
  Starts the `SlidingAlerter` process.

  ## Options

    * `:clock` — a zero-arity function returning the current time in
      milliseconds. Defaults to `fn -> System.monotonic_time(:millisecond) end`.
    * `:bucket_ms` — the width of each internal sub-bucket in milliseconds.
      Defaults to `1_000`.
    * `:threshold` — the event count within the window at or above which a key
      is considered to be in alarm. Defaults to `5`.
    * `:window_ms` — the sliding alerting window width in milliseconds.
      Defaults to `60_000`.
    * `:name` — optional process registration name.
    * `:cleanup_interval_ms` — how often to run the periodic cleanup. Defaults
      to `60_000`. Pass `:infinity` to disable.

  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    {name, init_opts} = Keyword.pop(opts, :name)

    case name do
      nil -> GenServer.start_link(__MODULE__, init_opts)
      name -> GenServer.start_link(__MODULE__, init_opts, name: name)
    end
  end

  @doc """
  Records one event for `key` at the current clock time and returns the key's
  resulting status (`:ok` or `:alarm`).
  """
  @spec record(GenServer.server(), key()) :: status()
  def record(server, key) do
    GenServer.call(server, {:record, key})
  end

  @doc """
  Returns `:ok` or `:alarm` for `key` based on the current clock time, without
  recording anything.
  """
  @spec status(GenServer.server(), key()) :: status()
  def status(server, key) do
    GenServer.call(server, {:status, key})
  end

  @doc """
  Returns the number of events recorded for `key` that fall within the last
  `:window_ms` milliseconds relative to the current clock time.
  """
  @spec count(GenServer.server(), key()) :: non_neg_integer()
  def count(server, key) do
    GenServer.call(server, {:count, key})
  end

  # GenServer callbacks

  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)

    state = %{
      clock: clock,
      bucket_ms: Keyword.get(opts, :bucket_ms, @default_bucket_ms),
      threshold: Keyword.get(opts, :threshold, @default_threshold),
      window_ms: Keyword.get(opts, :window_ms, @default_window_ms),
      cleanup_interval_ms: Keyword.get(opts, :cleanup_interval_ms, @default_cleanup_interval_ms),
      keys: %{}
    }

    schedule_cleanup(state.cleanup_interval_ms)
    {:ok, state}
  end

  @impl true
  def handle_call({:record, key}, _from, state) do
    now = state.clock.()
    bucket = div(now, state.bucket_ms)

    buckets =
      state.keys
      |> Map.get(key, %{})
      |> Map.update(bucket, 1, &(&1 + 1))

    state = %{state | keys: Map.put(state.keys, key, buckets)}
    {:reply, status_for(buckets, now, state), state}
  end

  @impl true
  def handle_call({:status, key}, _from, state) do
    now = state.clock.()
    buckets = Map.get(state.keys, key, %{})
    {:reply, status_for(buckets, now, state), state}
  end

  @impl true
  def handle_call({:count, key}, _from, state) do
    now = state.clock.()
    buckets = Map.get(state.keys, key, %{})
    {:reply, count_for(buckets, now, state), state}
  end

  def handle_info(:cleanup, state) do
    # TODO
  end

  # Internal helpers

  @spec schedule_cleanup(pos_integer() | :infinity) :: :ok
  defp schedule_cleanup(:infinity), do: :ok

  defp schedule_cleanup(interval_ms) when is_integer(interval_ms) do
    Process.send_after(self(), :cleanup, interval_ms)
    :ok
  end

  @spec count_for(map(), integer(), map()) :: non_neg_integer()
  defp count_for(buckets, now, state) do
    cutoff = now - state.window_ms

    Enum.reduce(buckets, 0, fn {bucket, count}, acc ->
      if bucket * state.bucket_ms >= cutoff, do: acc + count, else: acc
    end)
  end

  @spec status_for(map(), integer(), map()) :: status()
  defp status_for(buckets, now, state) do
    if count_for(buckets, now, state) >= state.threshold, do: :alarm, else: :ok
  end

  @spec cleanup(map()) :: map()
  defp cleanup(state) do
    now = state.clock.()
    cutoff = now - state.window_ms

    keys =
      state.keys
      |> Enum.reduce(%{}, fn {key, buckets}, acc ->
        live =
          buckets
          |> Enum.filter(fn {bucket, _count} -> bucket * state.bucket_ms >= cutoff end)
          |> Map.new()

        if map_size(live) == 0, do: acc, else: Map.put(acc, key, live)
      end)

    %{state | keys: keys}
  end
end
```

Give me only the complete implementation of `handle_info` (including the
`@doc`/`@spec`/`@impl` lines shown above it in the module, if any) — the
function alone, not the whole module.
