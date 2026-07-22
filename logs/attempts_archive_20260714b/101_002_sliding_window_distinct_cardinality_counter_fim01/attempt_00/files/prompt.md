Implement the `handle_call/3` GenServer callback for `SlidingUniqueCounter`. It has
three clauses, one for each synchronous request the public API sends.

1. `{:add, key, member}` — records an observation. Read the current time from
   `state.clock`, compute the bucket index as `div(now, state.bucket_ms)`, and add
   `member` to the `MapSet` stored for that key/bucket (creating the key map and the
   bucket set if they do not exist yet). Adding the same member again must leave the
   set unchanged. Reply with `:ok` and the updated state.

2. `{:distinct_count, key, window_ms}` — answers how many distinct members fall
   inside the window. Read `now` from `state.clock`, compute `threshold = now -
   window_ms`, and take the union of the member sets of every bucket for `key` whose
   start time (`index * state.bucket_ms`) is at or after `threshold`. Buckets whose
   start time is before `threshold` are ignored. Reply with the size of the union and
   the unchanged state.

3. `:tracked_key_count` — reply with the number of keys currently retained
   (`map_size(state.keys)`) and the unchanged state.

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

  def handle_call({:add, key, member}, _from, state) do
    # TODO
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