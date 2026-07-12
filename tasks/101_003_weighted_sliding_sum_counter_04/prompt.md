Implement the private `schedule_cleanup/1` function.

`schedule_cleanup/1` arranges for the periodic cleanup to run and always returns
the (unchanged) state so it can be threaded through `init/1` and the `:cleanup`
`handle_info/2` clause. Its behavior depends on the `:cleanup_interval_ms` field
of the state:

- When `cleanup_interval_ms` is `:infinity`, periodic cleanup is disabled: do
  not schedule anything and simply return the state unchanged.
- Otherwise, schedule a `:cleanup` message to be delivered to the current
  process (`self()`) after `cleanup_interval_ms` milliseconds using
  `Process.send_after/3`, then return the state unchanged.

The returned state must be identical to the input state in both cases — this
function is called purely for its scheduling side effect.

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

    {:ok, schedule_cleanup(state)}
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

  defp schedule_cleanup(%{cleanup_interval_ms: :infinity} = state) do
    # TODO
  end
end
```