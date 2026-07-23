# Fill in one @spec

Below: a working module where the `@spec` for
`start_link/1` has been removed (see the `# TODO: @spec` marker).
Provide exactly that typespec, consistent with the implementation's
arguments, guards, and all reachable return shapes. No other edits.

## The module with the `@spec` for `start_link/1` missing

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
  # TODO: @spec
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

The `@spec` attribute only — nothing more.
