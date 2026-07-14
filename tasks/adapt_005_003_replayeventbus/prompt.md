# Adapt existing code to a new specification

Below is a complete, working, tested Elixir solution to a related task. Do not
start from scratch: treat it as the codebase you have been asked to change.
Modify it to satisfy the new specification that follows — keep whatever carries
over, and change, add, or remove whatever the new specification requires.

Where the existing code and the new specification disagree (module name, public
API, behavior, constraints, output format), the new specification wins. Give me
the complete final result.

## Existing code (your starting point)

```elixir
defmodule EventBus do
  @moduledoc """
  An in-process pub/sub event bus with wildcard topic support.

  Topics are dot-separated strings (e.g. "orders.created").
  A "*" segment in a subscription pattern matches exactly one segment.
  """

  use GenServer

  # ── Client API ──────────────────────────────────────────────

  @doc "Starts the EventBus. Accepts a `:name` option for registration."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, init_opts} = Keyword.pop(opts, :name)
    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, init_opts, server_opts)
  end

  @doc "Subscribes `pid` to `topic`. Returns `{:ok, ref}`."
  @spec subscribe(GenServer.server(), String.t(), pid()) ::
          {:ok, reference()}
  def subscribe(server, topic, pid) do
    GenServer.call(server, {:subscribe, topic, pid})
  end

  @doc "Removes the subscription identified by `ref` from `topic`."
  @spec unsubscribe(GenServer.server(), String.t(), reference()) ::
          :ok
  def unsubscribe(server, topic, ref) do
    GenServer.call(server, {:unsubscribe, topic, ref})
  end

  @doc "Publishes `event` to all subscribers matching `topic`."
  @spec publish(GenServer.server(), String.t(), term()) :: :ok
  def publish(server, topic, event) do
    GenServer.call(server, {:publish, topic, event})
  end

  # ── Server Callbacks ────────────────────────────────────────

  @impl true
  def init(_opts) do
    # topics: %{topic_pattern => %{ref => pid}}
    # refs:   %{ref => {pid, topic_pattern}}
    # pids:   %{pid => MapSet.t(ref)}
    {:ok, %{topics: %{}, refs: %{}, pids: %{}}}
  end

  @impl true
  def handle_call({:subscribe, topic, pid}, _from, state) do
    ref = Process.monitor(pid)

    topics =
      Map.update(
        state.topics,
        topic,
        %{ref => pid},
        &Map.put(&1, ref, pid)
      )

    refs = Map.put(state.refs, ref, {pid, topic})

    pids =
      Map.update(
        state.pids,
        pid,
        MapSet.new([ref]),
        &MapSet.put(&1, ref)
      )

    {:reply, {:ok, ref}, %{state | topics: topics, refs: refs, pids: pids}}
  end

  def handle_call({:unsubscribe, topic, ref}, _from, state) do
    {:reply, :ok, drop_subscription(state, topic, ref)}
  end

  def handle_call({:publish, topic, event}, _from, state) do
    message = {:event, topic, event}

    Enum.each(state.topics, fn {pattern, subs} ->
      if topic_matches?(pattern, topic) do
        Enum.each(subs, fn {_ref, pid} ->
          send(pid, message)
        end)
      end
    end)

    {:reply, :ok, state}
  end

  @impl true
  def handle_info({:DOWN, down_ref, :process, pid, _reason}, state) do
    case Map.fetch(state.pids, pid) do
      {:ok, ref_set} ->
        Enum.each(ref_set, fn r ->
          if r != down_ref do
            Process.demonitor(r, [:flush])
          end
        end)

        state =
          Enum.reduce(ref_set, state, fn r, acc ->
            case Map.fetch(acc.refs, r) do
              {:ok, {_pid, topic}} ->
                drop_subscription_entry(acc, topic, r)

              :error ->
                acc
            end
          end)

        {:noreply, %{state | pids: Map.delete(state.pids, pid)}}

      :error ->
        {:noreply, state}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ── Internal Helpers ────────────────────────────────────────

  defp drop_subscription(state, topic, ref) do
    case Map.fetch(state.refs, ref) do
      {:ok, {pid, ^topic}} ->
        Process.demonitor(ref, [:flush])
        state = drop_subscription_entry(state, topic, ref)
        clean_pid_refs(state, pid, ref)

      _ ->
        state
    end
  end

  defp clean_pid_refs(state, pid, ref) do
    case Map.fetch(state.pids, pid) do
      {:ok, set} ->
        new_set = MapSet.delete(set, ref)

        if MapSet.size(new_set) == 0 do
          %{state | pids: Map.delete(state.pids, pid)}
        else
          %{state | pids: Map.put(state.pids, pid, new_set)}
        end

      :error ->
        state
    end
  end

  defp drop_subscription_entry(state, topic, ref) do
    refs = Map.delete(state.refs, ref)

    topics =
      case Map.fetch(state.topics, topic) do
        {:ok, subs} ->
          new_subs = Map.delete(subs, ref)

          if map_size(new_subs) == 0 do
            Map.delete(state.topics, topic)
          else
            Map.put(state.topics, topic, new_subs)
          end

        :error ->
          state.topics
      end

    %{state | topics: topics, refs: refs}
  end

  defp topic_matches?(pattern, topic) do
    p_parts = String.split(pattern, ".")
    t_parts = String.split(topic, ".")

    length(p_parts) == length(t_parts) and
      segments_match?(p_parts, t_parts)
  end

  defp segments_match?([], []), do: true
  defp segments_match?(["*" | pr], [_ | tr]), do: segments_match?(pr, tr)
  defp segments_match?([s | pr], [s | tr]), do: segments_match?(pr, tr)
  defp segments_match?(_, _), do: false
end
```

## New specification

Write me an Elixir GenServer module called `ReplayEventBus` that implements an in-process pub/sub event system where new subscribers can optionally receive the **last N events** published on a topic before starting to receive live events.

The motivation: in many systems a subscriber that joins mid-stream needs to catch up on what it missed — a state-sync layer needs the most recent snapshot, a late-arriving monitor needs to see recent errors. Standard pub/sub forces every subscriber to bootstrap from an external snapshot. This module gives the bus itself a bounded per-topic history.

I need these functions in the public API:

- `ReplayEventBus.start_link(opts)` accepts:
  - `:name` — optional process registration
  - `:default_history_size` — how many events to retain per topic by default (default `100`)
  - `:history_ttl_ms` — how long events are retained, in ms (default `3_600_000`, i.e. 1 hour). Events older than this are dropped lazily on publish and during the periodic cleanup sweep.
  - `:clock` — zero-arity function returning monotonic time in ms (default `fn -> System.monotonic_time(:millisecond) end`). Used for TTL math.
  - `:cleanup_interval_ms` — periodic sweep interval in ms (default `60_000`). Setting it to `:infinity` disables auto-cleanup (useful for testing).

- `ReplayEventBus.subscribe(server, topic, pid, opts \\ [])` subscribes `pid` to the exact topic (no wildcards). `opts` may contain `:replay` with values:
  - `:none` (default) — no replay, only live events from this point forward
  - `:all` — replay every retained event for this topic, then live events
  - positive integer `n` — replay the most recent `n` retained events, then live events

  Replayed events are sent **before** `subscribe/4` returns, in oldest-to-newest order, so the subscriber sees history in chronological order. The bus must `Process.monitor` the subscriber. Returns `{:ok, ref}`.

- `ReplayEventBus.unsubscribe(server, topic, ref)` removes the subscription. Demonitor the pid when its last subscription is removed. Returns `:ok`.

- `ReplayEventBus.publish(server, topic, event)` — sends `{:event, topic, event}` to every live subscriber (exact topic match only) AND appends the event to the topic's bounded history. History enforces two independent bounds:
  - Count bound: keep at most `history_size_for(topic)` most recent events
  - TTL bound: drop events older than `history_ttl_ms`

  Both bounds are enforced on every publish. Returns `:ok`.

- `ReplayEventBus.history(server, topic)` — returns a list of retained events for the topic in oldest-to-newest order, after applying the TTL (so stale events are not returned). Returns `[]` for unknown topics. Used mostly for debugging / inspection.

- `ReplayEventBus.set_history_size(server, topic, size)` — override the per-topic history size. `size` must be a non-negative integer; `0` disables history for that topic (existing entries are dropped). Returns `:ok`.

**Important semantics for replay-then-live**: replay must be atomic with the subscription becoming active. That is, between the last replayed event and the first live event the subscriber sees, no event can be missed or duplicated. Concretely:

1. Acquire a snapshot of the topic's history (after TTL eviction).
2. Select the last N events (or all, based on the replay option).
3. Send each historical event to the subscriber in order via `send/2`.
4. Register the subscriber in the topics map so future `publish/3` calls will deliver live events.

Because the whole subscribe handler runs inside a single GenServer call, steps 1–4 are atomic with respect to other publishes — an in-flight publish either precedes the replay (gets into history, so the subscriber sees it in step 3) or follows registration (delivered live in step 4). There's no window for missed or duplicated delivery, but a subscriber that subscribes *during* a publish might see the event twice in the worst case (once in replay, once live) — actually no: the subscribe call is serialized by the GenServer, so it either runs to completion before the publish starts or after it finishes.

Events are sent to subscribers in the shape `{:event, topic, event}` (same shape for replay and live — the subscriber can't distinguish them from the message alone).

When a monitored subscriber dies (`:DOWN` message), remove all its subscriptions across all topics. Do not purge the topic's history — history is per-topic, not per-subscriber.

Periodic cleanup via `Process.send_after(self(), :cleanup, cleanup_interval_ms)` evicts events older than the TTL across all topics. Topics whose history becomes empty AND who have zero subscribers are dropped entirely (indistinguishable from a never-seen topic).

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.
