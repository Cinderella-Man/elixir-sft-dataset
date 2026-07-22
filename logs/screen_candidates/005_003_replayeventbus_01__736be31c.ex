defmodule ReplayEventBus do
  @moduledoc """
  An in-process publish/subscribe event bus with bounded, replayable per-topic history.

  `ReplayEventBus` behaves like a conventional topic-based bus — publishers send events to a
  topic, and every subscriber of that exact topic (there are no wildcards) receives a
  `{:event, topic, event}` message — with one addition: the bus itself retains a bounded
  history of the most recent events per topic, and a new subscriber may ask to have that
  history *replayed* to it before it starts receiving live events.

  This removes the usual requirement that a late-joining subscriber bootstrap itself from an
  external snapshot: a state-sync layer can ask for the last event on a topic, and a monitor
  that starts after a burst of errors can ask for all retained events.

  ## History bounds

  Retention is governed by two independent bounds, both enforced on every publish (and again
  during the periodic cleanup sweep):

    * a **count bound** — at most `history_size_for(topic)` most recent events are kept
      (`:default_history_size`, overridable per topic with `set_history_size/3`);
    * a **TTL bound** — events older than `:history_ttl_ms` are evicted lazily.

  Time is read through the injectable `:clock` function (monotonic milliseconds), which makes
  TTL behaviour deterministically testable.

  ## Replay-then-live atomicity

  `subscribe/4` runs entirely inside a single `GenServer` call, so the following steps are
  atomic with respect to any concurrent `publish/3`:

    1. take a snapshot of the topic history (after TTL eviction);
    2. select the events to replay (`:all` or the last `n`);
    3. `send/2` them to the subscriber, oldest-to-newest;
    4. register the subscriber so subsequent publishes reach it live.

  A publish is therefore either fully ordered before the subscribe (it is already in the
  history and is seen during replay) or fully after it (the subscriber is registered and gets
  it live). No event can be missed or duplicated across the replay/live boundary.

  Replayed and live events are indistinguishable from the message alone: both arrive as
  `{:event, topic, event}`.

  ## Lifecycle

  Subscribers are monitored. When a subscriber dies, all of its subscriptions are removed from
  every topic; topic histories are untouched, since history belongs to the topic rather than to
  any subscriber. The periodic cleanup sweep evicts expired events and drops topics that end up
  with neither history nor subscribers, making them indistinguishable from never-seen topics.
  """

  use GenServer

  @default_history_size 100
  @default_history_ttl_ms 3_600_000
  @default_cleanup_interval_ms 60_000

  @typedoc "A topic identifier. Any term; matching is exact (no wildcards)."
  @type topic :: term()

  @typedoc "An arbitrary published event payload."
  @type event :: term()

  @typedoc "Opaque subscription reference returned by `subscribe/4`."
  @type subscription :: reference()

  @typedoc "Replay strategy for a new subscriber."
  @type replay :: :none | :all | pos_integer()

  @typedoc "Options accepted by `start_link/1`."
  @type option ::
          {:name, GenServer.name()}
          | {:default_history_size, non_neg_integer()}
          | {:history_ttl_ms, pos_integer() | :infinity}
          | {:clock, (-> integer())}
          | {:cleanup_interval_ms, pos_integer() | :infinity}

  # Per-topic entry:
  #   %{subscribers: %{subscription => pid}, history: [{ts, event}], size: nil | non_neg_integer}
  # `history` is kept oldest-to-newest. `size: nil` means "use the bus default".
  defstruct topics: %{},
            refs: %{},
            monitors: %{},
            default_history_size: @default_history_size,
            history_ttl_ms: @default_history_ttl_ms,
            clock: nil,
            cleanup_interval_ms: @default_cleanup_interval_ms

  ## Public API

  @doc """
  Starts the event bus.

  ## Options

    * `:name` — optional `GenServer` name registration.
    * `:default_history_size` — events retained per topic by default (default `100`).
    * `:history_ttl_ms` — retention window in milliseconds (default `3_600_000`). Older events
      are dropped lazily on publish and during the periodic cleanup sweep.
    * `:clock` — zero-arity function returning monotonic time in milliseconds
      (default `fn -> System.monotonic_time(:millisecond) end`). Used for all TTL math.
    * `:cleanup_interval_ms` — periodic sweep interval (default `60_000`); `:infinity` disables
      the automatic sweep, which is handy in tests.
  """
  @spec start_link([option()]) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)
    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, server_opts)
  end

  @doc """
  Subscribes `pid` to `topic` (exact match; no wildcards).

  Supported options:

    * `:replay` — `:none` (default) for live events only, `:all` to receive every retained
      event first, or a positive integer `n` to receive the most recent `n` retained events
      first.

  Replayed events are delivered with `send/2` in oldest-to-newest order and are all sent
  *before* this function returns, so the subscriber observes history in chronological order and
  then a gap-free live stream. The subscriber is monitored, so its subscriptions are cleaned up
  automatically if it dies.

  Returns `{:ok, ref}`, where `ref` identifies the subscription for `unsubscribe/3`.
  """
  @spec subscribe(GenServer.server(), topic(), pid(), keyword()) :: {:ok, subscription()}
  def subscribe(server, topic, pid, opts \\ []) when is_pid(pid) and is_list(opts) do
    replay = Keyword.get(opts, :replay, :none)

    unless valid_replay?(replay) do
      raise ArgumentError,
            "invalid :replay option #{inspect(replay)}; expected :none, :all or a positive integer"
    end

    GenServer.call(server, {:subscribe, topic, pid, replay})
  end

  @doc """
  Removes the subscription identified by `ref` from `topic`.

  The subscriber is demonitored once its last subscription (across all topics) is gone. Unknown
  or already-removed references are ignored. Always returns `:ok`.
  """
  @spec unsubscribe(GenServer.server(), topic(), subscription()) :: :ok
  def unsubscribe(server, topic, ref) when is_reference(ref) do
    GenServer.call(server, {:unsubscribe, topic, ref})
  end

  @doc """
  Publishes `event` on `topic`.

  Every live subscriber of the exact topic receives `{:event, topic, event}`, and the event is
  appended to the topic's bounded history. Both the count bound and the TTL bound are enforced
  on every publish. Returns `:ok`.
  """
  @spec publish(GenServer.server(), topic(), event()) :: :ok
  def publish(server, topic, event) do
    GenServer.call(server, {:publish, topic, event})
  end

  @doc """
  Returns the retained events for `topic`, oldest-to-newest, after applying the TTL.

  Stale events are never returned (and are evicted as a side effect). Unknown topics return
  `[]`. Intended mainly for debugging and inspection.
  """
  @spec history(GenServer.server(), topic()) :: [event()]
  def history(server, topic) do
    GenServer.call(server, {:history, topic})
  end

  @doc """
  Overrides the number of events retained for `topic`.

  `size` must be a non-negative integer. `0` disables history for the topic and drops any
  entries it currently holds. Existing history longer than the new size is truncated to the most
  recent `size` events. Returns `:ok`.
  """
  @spec set_history_size(GenServer.server(), topic(), non_neg_integer()) :: :ok
  def set_history_size(server, topic, size) when is_integer(size) and size >= 0 do
    GenServer.call(server, {:set_history_size, topic, size})
  end

  ## GenServer callbacks

  @impl true
  def init(opts) do
    state = %__MODULE__{
      default_history_size: Keyword.get(opts, :default_history_size, @default_history_size),
      history_ttl_ms: Keyword.get(opts, :history_ttl_ms, @default_history_ttl_ms),
      clock: Keyword.get(opts, :clock, &default_clock/0),
      cleanup_interval_ms: Keyword.get(opts, :cleanup_interval_ms, @default_cleanup_interval_ms)
    }

    schedule_cleanup(state.cleanup_interval_ms)
    {:ok, state}
  end

  @impl true
  def handle_call({:subscribe, topic, pid, replay}, _from, state) do
    now = now(state)
    entry = topic_entry(state, topic)
    entry = prune_entry(entry, now, state)

    entry.history
    |> select_replay(replay)
    |> Enum.each(fn {_ts, event} -> send(pid, {:event, topic, event}) end)

    ref = make_ref()
    entry = %{entry | subscribers: Map.put(entry.subscribers, ref, pid)}

    state =
      state
      |> put_topic(topic, entry)
      |> Map.update!(:refs, &Map.put(&1, ref, {topic, pid}))
      |> monitor_pid(pid)

    {:reply, {:ok, ref}, state}
  end

  def handle_call({:unsubscribe, topic, ref}, _from, state) do
    {:reply, :ok, remove_subscription(state, topic, ref)}
  end

  def handle_call({:publish, topic, event}, _from, state) do
    now = now(state)
    entry = state |> topic_entry(topic) |> prune_entry(now, state)

    Enum.each(entry.subscribers, fn {_ref, pid} -> send(pid, {:event, topic, event}) end)

    entry =
      %{entry | history: entry.history ++ [{now, event}]}
      |> enforce_count_bound(state)

    {:reply, :ok, put_topic(state, topic, entry)}
  end

  def handle_call({:history, topic}, _from, state) do
    now = now(state)
    entry = state |> topic_entry(topic) |> prune_entry(now, state)
    events = Enum.map(entry.history, fn {_ts, event} -> event end)
    {:reply, events, put_topic(state, topic, entry)}
  end

  def handle_call({:set_history_size, topic, size}, _from, state) do
    entry =
      state
      |> topic_entry(topic)
      |> Map.put(:size, size)
      |> prune_entry(now(state), state)

    {:reply, :ok, put_topic(state, topic, entry)}
  end

  @impl true
  def handle_info({:DOWN, _monitor_ref, :process, pid, _reason}, state) do
    refs = for {ref, {topic, ^pid}} <- state.refs, do: {topic, ref}

    state =
      Enum.reduce(refs, state, fn {topic, ref}, acc ->
        remove_subscription(acc, topic, ref, demonitor: false)
      end)

    {:noreply, %{state | monitors: Map.delete(state.monitors, pid)}}
  end

  def handle_info(:cleanup, state) do
    now = now(state)

    topics =
      state.topics
      |> Enum.map(fn {topic, entry} -> {topic, prune_entry(entry, now, state)} end)
      |> Enum.reject(fn {_topic, entry} -> discardable?(entry) end)
      |> Map.new()

    schedule_cleanup(state.cleanup_interval_ms)
    {:noreply, %{state | topics: topics}}
  end

  def handle_info(_message, state), do: {:noreply, state}

  ## Internal helpers

  defp default_clock, do: System.monotonic_time(:millisecond)

  defp now(%__MODULE__{clock: clock}), do: clock.()

  defp schedule_cleanup(:infinity), do: :ok

  defp schedule_cleanup(interval) when is_integer(interval) and interval > 0 do
    Process.send_after(self(), :cleanup, interval)
    :ok
  end

  defp valid_replay?(:none), do: true
  defp valid_replay?(:all), do: true
  defp valid_replay?(n) when is_integer(n) and n > 0, do: true
  defp valid_replay?(_other), do: false

  defp select_replay(_history, :none), do: []
  defp select_replay(history, :all), do: history
  defp select_replay(history, n) when is_integer(n) and n > 0, do: Enum.take(history, -n)

  defp new_entry, do: %{subscribers: %{}, history: [], size: nil}

  defp topic_entry(state, topic), do: Map.get(state.topics, topic) || new_entry()

  defp put_topic(state, topic, entry), do: %{state | topics: Map.put(state.topics, topic, entry)}

  # Applies both retention bounds: TTL first, then the count bound.
  defp prune_entry(entry, now, state) do
    entry
    |> drop_expired(now, state.history_ttl_ms)
    |> enforce_count_bound(state)
  end

  defp drop_expired(entry, _now, :infinity), do: entry

  defp drop_expired(entry, now, ttl) when is_integer(ttl) do
    cutoff = now - ttl
    %{entry | history: Enum.drop_while(entry.history, fn {ts, _event} -> ts < cutoff end)}
  end

  defp enforce_count_bound(entry, state) do
    case size_for(entry, state) do
      0 -> %{entry | history: []}
      size -> %{entry | history: Enum.take(entry.history, -size)}
    end
  end

  defp size_for(%{size: nil}, state), do: state.default_history_size
  defp size_for(%{size: size}, _state), do: size

  defp discardable?(entry), do: entry.history == [] and map_size(entry.subscribers) == 0

  defp remove_subscription(state, topic, ref, opts \\ []) do
    case Map.fetch(state.refs, ref) do
      {:ok, {^topic, pid}} ->
        entry = topic_entry(state, topic)
        entry = %{entry | subscribers: Map.delete(entry.subscribers, ref)}

        state =
          state
          |> put_topic(topic, entry)
          |> Map.update!(:refs, &Map.delete(&1, ref))

        if Keyword.get(opts, :demonitor, true) do
          maybe_demonitor(state, pid)
        else
          state
        end

      _other ->
        state
    end
  end

  defp monitor_pid(state, pid) do
    case Map.fetch(state.monitors, pid) do
      {:ok, _monitor_ref} ->
        state

      :error ->
        monitor_ref = Process.monitor(pid)
        %{state | monitors: Map.put(state.monitors, pid, monitor_ref)}
    end
  end

  defp maybe_demonitor(state, pid) do
    still_subscribed? = Enum.any?(state.refs, fn {_ref, {_topic, p}} -> p == pid end)

    case {still_subscribed?, Map.fetch(state.monitors, pid)} do
      {false, {:ok, monitor_ref}} ->
        Process.demonitor(monitor_ref, [:flush])
        %{state | monitors: Map.delete(state.monitors, pid)}

      _other ->
        state
    end
  end
end