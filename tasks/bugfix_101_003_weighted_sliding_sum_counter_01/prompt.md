# Debug and repair this module

A colleague shipped the module below for the task described next, and one
behavior bug made it through review. The test suite (not shown here)
produces the failure report at the bottom. Track the bug down and repair
it — keep the diff minimal and leave working code exactly as it is. Reply
with the complete corrected module.

## What the module is supposed to do

Write me an Elixir GenServer module called `SlidingSum` that maintains a sliding
time-window running **sum of numeric amounts** per key, using a sub-bucket
strategy.

Unlike a plain event counter, each recorded event carries a numeric amount
(think bytes transferred, dollars spent, or points scored), and queries return
the total amount within the window rather than a count of events.

I need these functions in the public API:
- `SlidingSum.start_link(opts)` to start the process. It should accept:
  - `:clock` — a zero-arity function returning the current time in milliseconds.
    Defaults to `fn -> System.monotonic_time(:millisecond) end`.
  - `:bucket_ms` — the width of each internal sub-bucket in milliseconds.
    Defaults to `1_000` (1 second).
  - `:name` — optional process registration name.
  - `:cleanup_interval_ms` — how often to run the periodic cleanup.
    Defaults to `60_000`. Pass `:infinity` to disable.
- `SlidingSum.add(server, key, amount)` — records `amount` (any number: it may be
  an integer or a float, and it may be negative) for the given key at the current
  clock time. Returns `:ok`.
- `SlidingSum.sum(server, key, window_ms)` — returns the total of all amounts
  recorded for `key` that fall within the last `window_ms` milliseconds relative
  to the current clock time. Amounts outside that window must not be included.
- `SlidingSum.keys(server)` — returns the list of keys currently tracked (those
  that still have at least one stored bucket), in no particular order. A server
  with no data returns `[]`, and once cleanup has removed every bucket of a key,
  that key no longer appears.

Semantics and internal design requirements:
- A key that has had no amounts added returns a sum of `0`.
- Divide time into fixed-width sub-buckets of `:bucket_ms` each. Every event is
  placed into the bucket whose index is `div(timestamp, bucket_ms)`, and each
  bucket accumulates the sum of the amounts placed into it.
- When answering `sum/3`, include a bucket iff its start time falls within the
  sliding window — that is, include bucket `b` iff `b * bucket_ms >= now - window_ms`.
  Discard (do not include) any bucket that starts before the window.
- Negative amounts subtract from the running window sum; a sum may therefore be
  negative or zero.
- Different keys must be tracked independently — adding to `"conn:a"` must not
  affect `"conn:b"`.
- Memory must not leak: the GenServer state must store per-key bucket sums under
  `state.keys`. Run a periodic cleanup (via `Process.send_after`) that removes
  buckets — and whole keys — that have fallen outside the maximum retention
  window of **24 hours** (`24 * 60 * 60 * 1000` ms): a bucket is retained by
  cleanup exactly when its start time satisfies the same inclusive rule as
  `sum/3`, i.e. `bucket_start >= now - 86_400_000` — a bucket starting exactly
  on that horizon survives. Also handle a `:cleanup` message sent directly to
  the process so tests can trigger cleanup synchronously. After cleanup,
  `state.keys` must be an empty
  map when all data has expired.

Give me the complete module in a single file. Use only the OTP standard library,
no external dependencies.

## The buggy module

```elixir
defmodule SlidingSum do
  @moduledoc """
  A GenServer that maintains a sliding time-window running **sum of numeric
  amounts** per key, using a sub-bucket strategy.

  Each recorded event carries a numeric amount (bytes transferred, dollars
  spent, points scored, ...). Time is divided into fixed-width sub-buckets of
  `:bucket_ms` milliseconds. Every event is placed into the bucket whose index
  is `div(timestamp, bucket_ms)`, and each bucket accumulates the sum of the
  amounts placed into it.

  When answering `sum/3`, a bucket `b` is included iff its start time falls
  within the sliding window, i.e. `b * bucket_ms >= now - window_ms`. Amounts
  may be integers or floats, and may be negative, so a windowed sum may be
  negative or zero.

  A periodic cleanup (scheduled with `Process.send_after/3`) removes buckets —
  and whole keys — that have fallen outside a reasonable maximum window, so the
  process does not leak memory. A `:cleanup` message may also be sent directly
  to the process to trigger cleanup synchronously (useful for tests).
  """

  use GenServer

  @default_bucket_ms 1_000
  @default_cleanup_interval_ms 60_000

  # Buckets older than this many window-milliseconds are considered expired by
  # the periodic cleanup. It is a generous upper bound on any expected window.
  @max_window_ms 24 * 60 * 60 * 1_000

  @typedoc "A user-supplied key. Any term may be used."
  @type key :: term()

  @typedoc "State held by the server."
  @type state :: %{
          clock: (-> integer()),
          bucket_ms: pos_integer(),
          cleanup_interval_ms: pos_integer() | :infinity,
          keys: %{optional(key()) => %{optional(integer()) => number()}}
        }

  @doc """
  Starts the `SlidingSum` server.

  ## Options

    * `:clock` — a zero-arity function returning the current time in
      milliseconds. Defaults to `fn -> System.monotonic_time(:millisecond) end`.
    * `:bucket_ms` — the width of each internal sub-bucket in milliseconds.
      Defaults to `1_000`.
    * `:name` — optional process registration name.
    * `:cleanup_interval_ms` — how often to run the periodic cleanup. Defaults
      to `60_000`. Pass `:infinity` to disable periodic cleanup.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @doc """
  Records `amount` for `key` at the current clock time.

  `amount` may be any number: an integer or a float, and it may be negative.
  This call is synchronous so that the amount is guaranteed to be recorded at
  the clock time observed when `add/3` is invoked. Always returns `:ok`.
  """
  @spec add(GenServer.server(), key(), number()) :: :ok
  def add(server, key, amount) when is_number(amount) do
    GenServer.call(server, {:add, key, amount})
  end

  @doc """
  Returns the total of all amounts recorded for `key` that fall within the last
  `window_ms` milliseconds relative to the current clock time.

  Amounts outside the window are not included. A key with no recorded amounts
  returns `0`.
  """
  @spec sum(GenServer.server(), key(), non_neg_integer()) :: number()
  def sum(server, key, window_ms) when is_integer(window_ms) and window_ms >= 0 do
    GenServer.call(server, {:sum, key, window_ms})
  end

  @doc """
  Returns the list of keys currently tracked by the server.

  A key appears only while it still has at least one bucket retained in state.
  After a cleanup removes all of a key's buckets, the key is dropped and will
  not be returned here. Intended for introspection and tests, this lets callers
  observe cleanup behavior through the public API rather than internal state.
  """
  @spec keys(GenServer.server()) :: [key()]
  def keys(server) do
    GenServer.call(server, :keys)
  end

  @impl true
  @spec init(keyword()) :: {:ok, state()}
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    bucket_ms = Keyword.get(opts, :bucket_ms, @default_bucket_ms)
    cleanup_interval_ms = Keyword.get(opts, :cleanup_interval_ms, @default_cleanup_interval_ms)

    state = %{
      clock: clock,
      bucket_ms: bucket_ms,
      cleanup_interval_ms: cleanup_interval_ms,
      keys: %{}
    }

    {:error, schedule_cleanup(state)}
  end

  @impl true
  def handle_call({:add, key, amount}, _from, state) do
    now = state.clock.()
    bucket = div(now, state.bucket_ms)

    buckets = Map.get(state.keys, key, %{})
    buckets = Map.update(buckets, bucket, amount, &(&1 + amount))
    keys = Map.put(state.keys, key, buckets)

    {:reply, :ok, %{state | keys: keys}}
  end

  def handle_call({:sum, key, window_ms}, _from, state) do
    now = state.clock.()
    cutoff = now - window_ms

    total =
      state.keys
      |> Map.get(key, %{})
      |> Enum.reduce(0, fn {bucket, bucket_sum}, acc ->
        if bucket * state.bucket_ms >= cutoff, do: acc + bucket_sum, else: acc
      end)

    {:reply, total, state}
  end

  def handle_call(:keys, _from, state) do
    {:reply, Map.keys(state.keys), state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    {:noreply, state |> cleanup() |> schedule_cleanup()}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @spec cleanup(state()) :: state()
  defp cleanup(state) do
    now = state.clock.()
    cutoff = now - @max_window_ms

    keys =
      state.keys
      |> Enum.reduce(%{}, fn {key, buckets}, acc ->
        kept =
          Enum.filter(buckets, fn {bucket, _sum} ->
            bucket * state.bucket_ms >= cutoff
          end)

        if kept == [], do: acc, else: Map.put(acc, key, Map.new(kept))
      end)

    %{state | keys: keys}
  end

  @spec schedule_cleanup(state()) :: state()
  defp schedule_cleanup(%{cleanup_interval_ms: :infinity} = state), do: state

  defp schedule_cleanup(state) do
    Process.send_after(self(), :cleanup, state.cleanup_interval_ms)
    state
  end
end
```

## Failing test report

```
12 of 12 test(s) failed:

  * test sum is zero for a key that has had nothing added
      no match of right hand side value:
      
          {:error,
           %{
             keys: %{},
             clock: &SlidingSumTest.Clock.now/0,
             bucket_ms: 100,
             cleanup_interval_ms: :infinity
           }}
      

  * test a single amount is summed within the window
      no match of right hand side value:
      
          {:error,
           %{
             keys: %{},
             clock: &SlidingSumTest.Clock.now/0,
             bucket_ms: 100,
             cleanup_interval_ms: :infinity
           }}
      

  * test multiple amounts are summed within the window
      no match of right hand side value:
      
          {:error,
           %{
             keys: %{},
             clock: &SlidingSumTest.Clock.now/0,
             bucket_ms: 100,
             cleanup_interval_ms: :infinity
           }}
      

  * test float amounts are summed
      no match of right hand side value:
      
          {:error,
           %{
             keys: %{},
             clock: &SlidingSumTest.Clock.now/0,
             bucket_ms: 100,
             cleanup_interval_ms: :infinity
           }}
      

  (…8 more)
```
