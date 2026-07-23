# Write the test harness

Module and original specification below. Produce the ExUnit harness that
verifies a correct implementation.

Hard requirements:
- Test module: `<Module>Test`, `use ExUnit.Case, async: false`.
- No `ExUnit.start()` (the evaluator owns startup).
- Self-contained single file: inline any fakes, clock Agents, and helpers.
- Full public API coverage plus the specification's edge cases.
- Compiles with zero warnings (`_`-prefix unused variables; float zero
  matches as `+0.0`/`-0.0`).

## Original specification

Write me an Elixir GenServer module called `ReplayEventBus` that implements an in-process pub/sub event system where new subscribers can optionally receive the **last N events** published on a topic before starting to receive live events.

The motivation: in many systems a subscriber that joins mid-stream needs to catch up on what it missed — a state-sync layer needs the most recent snapshot, a late-arriving monitor needs to see recent errors. Standard pub/sub forces every subscriber to bootstrap from an external snapshot. This module gives the bus itself a bounded per-topic history.

I need these functions in the public API:

- `ReplayEventBus.start_link(opts)` accepts:
  - `:name` — optional process registration
  - `:default_history_size` — how many events to retain per topic by default (default `100`)
  - `:history_ttl_ms` — how long events are retained, in ms (default `3_600_000`, i.e. 1 hour). Only events **strictly** older than this are dropped — an event aged exactly `history_ttl_ms` is still retained. Dropping happens lazily on publish, on read, and during the periodic cleanup sweep.
  - `:clock` — zero-arity function returning monotonic time in ms (default `fn -> System.monotonic_time(:millisecond) end`). Used for TTL math.
  - `:cleanup_interval_ms` — periodic sweep interval in ms (default `60_000`). Setting it to `:infinity` disables auto-cleanup (useful for testing).

- `ReplayEventBus.subscribe(server, topic, pid, opts \\ [])` subscribes `pid` to the exact topic (no wildcards). `opts` may contain `:replay` with values:
  - `:none` (default) — no replay, only live events from this point forward
  - `:all` — replay every retained event for this topic, then live events
  - positive integer `n` — replay the most recent `n` retained events, then live events

  Replayed events are sent **before** `subscribe/4` returns, in oldest-to-newest order, so the subscriber sees history in chronological order. The bus must `Process.monitor` the subscriber. Returns `{:ok, ref}`. Each call creates an independent subscription with its own `ref`, so a single pid that subscribes N times to a topic receives N copies of each live event.

- `ReplayEventBus.unsubscribe(server, topic, ref)` removes the subscription. Demonitor the pid when its last subscription is removed. Returns `:ok`.

- `ReplayEventBus.publish(server, topic, event)` — sends `{:event, topic, event}` to every live subscriber (exact topic match only) AND appends the event to the topic's bounded history. History enforces two independent bounds:
  - Count bound: keep at most `history_size_for(topic)` most recent events
  - TTL bound: drop events older than `history_ttl_ms`

  Both bounds are enforced on every publish. Returns `:ok`.

- `ReplayEventBus.history(server, topic)` — returns a list of retained events for the topic in oldest-to-newest order, after applying the TTL (so stale events are not returned). Returns `[]` for unknown topics. Used mostly for debugging / inspection.

- `ReplayEventBus.set_history_size(server, topic, size)` — override the per-topic history size. `size` must be a non-negative integer; `0` disables history for that topic (existing entries are dropped). Returns `:ok`. Enforce the non-negative requirement with a function guard, so passing a negative `size` raises `FunctionClauseError`.

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

## Module under test

```elixir
defmodule ReplayEventBus do
  @moduledoc """
  An in-process pub/sub event bus with per-topic bounded replay history.

  Each topic retains the last N events (bounded by count, and independently
  by age via a TTL).  A new subscriber may ask to receive the last K events
  at subscription time, before live delivery begins.  Because the subscribe
  handler runs inside a single GenServer call, replay-and-then-register is
  atomic with respect to other publishes — no event can be missed or
  duplicated between replay and live.

  State:

      %{
        topics: %{
          topic => %{
            # list of {ts_ms, event}, oldest first
            history: [],
            history_size: pos_integer,
            # list of %{ref, pid}, oldest subscription first
            subs: []
          }
        },
        monitors: %{ref => {pid, topic}},
        clock, default_history_size, history_ttl_ms, cleanup_interval_ms
      }

  ## Options

    * `:name`                  – optional process registration
    * `:default_history_size`  – default retained events per topic (default 100)
    * `:history_ttl_ms`        – retention age limit (default 3_600_000)
    * `:clock`                 – `(-> integer())` monotonic time in ms
    * `:cleanup_interval_ms`   – periodic sweep interval (default 60_000)

  """

  use GenServer

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)
    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, server_opts)
  end

  @doc "Subscribes `pid` to `topic`, optionally replaying buffered events. Returns `{:ok, ref}`."
  @spec subscribe(GenServer.server(), String.t(), pid(), keyword()) :: {:ok, reference()}
  def subscribe(server, topic, pid, opts \\ [])
      when is_binary(topic) and is_pid(pid) and is_list(opts) do
    GenServer.call(server, {:subscribe, topic, pid, opts})
  end

  @spec unsubscribe(GenServer.server(), String.t(), reference()) :: :ok
  def unsubscribe(server, topic, ref), do: GenServer.call(server, {:unsubscribe, topic, ref})

  @spec publish(GenServer.server(), String.t(), term()) :: :ok
  def publish(server, topic, event) when is_binary(topic) do
    GenServer.call(server, {:publish, topic, event})
  end

  @spec history(GenServer.server(), String.t()) :: [term()]
  def history(server, topic) when is_binary(topic) do
    GenServer.call(server, {:history, topic})
  end

  @spec set_history_size(GenServer.server(), String.t(), non_neg_integer()) :: :ok
  def set_history_size(server, topic, size)
      when is_binary(topic) and is_integer(size) and size >= 0 do
    GenServer.call(server, {:set_history_size, topic, size})
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    cleanup_interval = Keyword.get(opts, :cleanup_interval_ms, 60_000)

    schedule_cleanup(cleanup_interval)

    {:ok,
     %{
       topics: %{},
       monitors: %{},
       clock: clock,
       default_history_size: Keyword.get(opts, :default_history_size, 100),
       history_ttl_ms: Keyword.get(opts, :history_ttl_ms, 3_600_000),
       cleanup_interval_ms: cleanup_interval
     }}
  end

  @impl true
  def handle_call({:subscribe, topic, pid, sub_opts}, _from, state) do
    now = state.clock.()
    replay = Keyword.get(sub_opts, :replay, :none)

    topic_state =
      state.topics
      |> Map.get(topic, fresh_topic(state.default_history_size))
      |> evict_expired(now, state.history_ttl_ms)

    # Send replay events BEFORE registering, preserving oldest→newest order.
    replay_events(topic_state.history, replay, pid, topic)

    monitor_ref = Process.monitor(pid)

    new_topic_state = %{
      topic_state
      | subs: topic_state.subs ++ [%{ref: monitor_ref, pid: pid}]
    }

    # A fresh `Process.monitor/1` ref per subscribe: the key can never
    # pre-exist, and each ref guards exactly the one topic it was minted for.
    monitors = Map.put(state.monitors, monitor_ref, {pid, topic})

    new_state = %{
      state
      | topics: Map.put(state.topics, topic, new_topic_state),
        monitors: monitors
    }

    {:reply, {:ok, monitor_ref}, new_state}
  end

  def handle_call({:unsubscribe, topic, ref}, _from, state) do
    new_state = remove_ref_from_topic(state, topic, ref)
    {:reply, :ok, new_state}
  end

  def handle_call({:publish, topic, event}, _from, state) do
    now = state.clock.()

    topic_state =
      state.topics
      |> Map.get(topic, fresh_topic(state.default_history_size))
      |> evict_expired(now, state.history_ttl_ms)

    # Deliver live to all current subscribers
    Enum.each(topic_state.subs, fn %{pid: pid} ->
      send(pid, {:event, topic, event})
    end)

    # Append to history, enforce count bound
    new_history =
      (topic_state.history ++ [{now, event}])
      |> Enum.take(-topic_state.history_size)

    new_topic_state = %{topic_state | history: new_history}

    {:reply, :ok, %{state | topics: Map.put(state.topics, topic, new_topic_state)}}
  end

  def handle_call({:history, topic}, _from, state) do
    now = state.clock.()

    case Map.get(state.topics, topic) do
      nil ->
        {:reply, [], state}

      t ->
        fresh = evict_expired(t, now, state.history_ttl_ms)
        events = Enum.map(fresh.history, fn {_ts, evt} -> evt end)
        {:reply, events, %{state | topics: Map.put(state.topics, topic, fresh)}}
    end
  end

  def handle_call({:set_history_size, topic, size}, _from, state) do
    topic_state =
      state.topics
      |> Map.get(topic, fresh_topic(state.default_history_size))
      |> Map.put(:history_size, size)

    # Trim existing history to new size.
    trimmed = Enum.take(topic_state.history, -size)
    new_topic_state = %{topic_state | history: trimmed}

    {:reply, :ok, %{state | topics: Map.put(state.topics, topic, new_topic_state)}}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case Map.pop(state.monitors, ref) do
      {nil, _} ->
        {:noreply, state}

      {{_pid, topic}, monitors} ->
        new_topics =
          case Map.get(state.topics, topic) do
            nil ->
              state.topics

            t ->
              Map.put(state.topics, topic, %{t | subs: Enum.reject(t.subs, &(&1.ref == ref))})
          end

        {:noreply, %{state | topics: new_topics, monitors: monitors}}
    end
  end

  def handle_info(:cleanup, state) do
    now = state.clock.()

    new_topics =
      Enum.reduce(state.topics, %{}, fn {name, t}, acc ->
        fresh = evict_expired(t, now, state.history_ttl_ms)

        # Drop topics with empty history AND no subscribers.
        if fresh.history == [] and fresh.subs == [] do
          acc
        else
          Map.put(acc, name, fresh)
        end
      end)

    schedule_cleanup(state.cleanup_interval_ms)
    {:noreply, %{state | topics: new_topics}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Replay selection
  # ---------------------------------------------------------------------------

  # history is oldest-first list of {ts, event}.
  defp replay_events(_history, :none, _pid, _topic), do: :ok

  defp replay_events(history, :all, pid, topic) do
    Enum.each(history, fn {_ts, evt} -> send(pid, {:event, topic, evt}) end)
  end

  defp replay_events(history, n, pid, topic) when is_integer(n) and n > 0 do
    # Enum.take(-n) grabs the n last elements in oldest-first order.
    history
    |> Enum.take(-n)
    |> Enum.each(fn {_ts, evt} -> send(pid, {:event, topic, evt}) end)
  end

  defp replay_events(_, _, _, _), do: :ok

  # ---------------------------------------------------------------------------
  # Topic state helpers
  # ---------------------------------------------------------------------------

  defp fresh_topic(default_size), do: %{history: [], history_size: default_size, subs: []}

  # Drop entries older than TTL.  history is oldest-first, so we can stop at
  # the first non-expired entry.
  defp evict_expired(t, now, ttl_ms) do
    cutoff = now - ttl_ms

    live =
      Enum.drop_while(t.history, fn {ts, _evt} -> ts < cutoff end)

    %{t | history: live}
  end

  defp remove_ref_from_topic(state, topic, ref) do
    case Map.get(state.topics, topic) do
      nil ->
        state

      t ->
        new_subs = Enum.reject(t.subs, &(&1.ref == ref))
        topics = Map.put(state.topics, topic, %{t | subs: new_subs})

        # Each ref guards exactly one topic (see subscribe), so removing the
        # subscription always retires the whole monitor.
        monitors =
          if Map.has_key?(state.monitors, ref) do
            Process.demonitor(ref, [:flush])
            Map.delete(state.monitors, ref)
          else
            state.monitors
          end

        %{state | topics: topics, monitors: monitors}
    end
  end

  defp schedule_cleanup(:infinity), do: :ok

  defp schedule_cleanup(ms) when is_integer(ms) and ms > 0 do
    Process.send_after(self(), :cleanup, ms)
  end
end
```
