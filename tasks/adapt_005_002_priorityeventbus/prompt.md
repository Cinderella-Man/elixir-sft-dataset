# Migrate existing code to a new spec

Starting point: the working, tested solution below, from a related task.
Change it — no ground-up rewrite — until it satisfies the specification
that follows. On any disagreement between the two (module name, public API,
behavior, constraints, output format), the new specification wins. Output
the complete updated code.

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

Write me an Elixir GenServer module called `PriorityEventBus` that implements an in-process pub/sub event system where subscribers receive events in **priority order**, and high-priority subscribers can **veto** delivery to lower-priority ones.

The motivation: plain pub/sub fans out every event to every subscriber concurrently, with no ordering between handlers. In some designs you want layered handling: a validator that runs first and can block subsequent processing; an audit logger that must observe an event before user-visible handlers get it; a cache invalidator that runs before the cache-consumer. This module adds priority ordering and a cancellation channel for these layered designs.

I need these functions in the public API:

- `PriorityEventBus.start_link(opts)` to start the process. It should accept a `:name` option for process registration. It should also accept a `:delivery_timeout_ms` option (default `5_000`) — the maximum time the bus will wait for a single subscriber's ack before moving on (see below).

- `PriorityEventBus.subscribe(server, topic, pid, priority)` subscribes `pid` to the exact topic string. `priority` is an integer — higher values run earlier. The bus must `Process.monitor` the subscriber. Returns `{:ok, ref}` where `ref` is the monitor reference and serves as the subscription identifier.

- `PriorityEventBus.unsubscribe(server, topic, ref)` removes the subscription. Demonitor the process if this was its last subscription. Returns `:ok`.

- `PriorityEventBus.publish(server, topic, event)` — this is where the semantics diverge from standard pub/sub. For each subscriber matching the topic (**exact match only — no wildcards**), in descending priority order:
  1. Send `{:event, topic, event, reply_to}` to the subscriber, where `reply_to` is `{pid_of_bus, unique_ref}`.
  2. Block waiting for the subscriber to reply with either `{:ack, unique_ref}` (continue delivery) or `{:cancel, unique_ref}` (stop delivery to all remaining lower-priority subscribers).
  3. If no reply arrives within `delivery_timeout_ms`, treat it as `:ack` (don't cancel downstream) and move on.
  4. Ties within the same priority level are delivered **in subscription order** (oldest subscription first), still respecting ack/cancel semantics.

  Returns `{:ok, delivered_count}`. `delivered_count` is the number of subscribers the bus reached (sent the event to) before delivery stopped. Every subscriber the bus reaches counts — including one that acks, one that cancels, one that times out without replying, and one that dies mid-delivery. The only subscribers **not** counted are the lower-priority ones the bus never reached because an earlier subscriber cancelled. So a top-priority cancel with two lower subscribers returns `{:ok, 1}`; a mid-priority cancel that follows one acking subscriber returns `{:ok, 2}`.

- `PriorityEventBus.ack(reply_to)` — convenience helper that a subscriber can call from its handler. `reply_to` is the `{bus_pid, unique_ref}` tuple the subscriber received. Sends `{:ack, unique_ref}` to `bus_pid`. Returns `:ok`.

- `PriorityEventBus.cancel(reply_to)` — like `ack/1` but sends `{:cancel, unique_ref}`. Used by high-priority handlers to veto delivery to lower-priority ones. Returns `:ok`.

- `PriorityEventBus.subscribers(server, topic)` — returns a list of `{ref, pid, priority}` tuples for all subscribers of a topic, sorted by descending priority then by subscription order within a priority level. Returns `[]` if no subscribers.

Ordering details to be precise about:

- Within a publish, subscribers are processed strictly serially (one at a time, awaiting each ack/cancel before starting the next). This is the opposite of standard fan-out pub/sub.
- Because publish blocks the GenServer on each subscriber's reply, any other call to the bus is queued behind an in-flight publish. This is intentional — it's the price of deterministic priority ordering.
- A subscriber's handler must run in the subscriber's own process (not inside the bus), so the bus uses `send/2` + a receive inside the publish handler, NOT `GenServer.call` on the subscriber.
- Each event delivery uses a fresh `unique_ref`, and the bus only accepts a reply whose ref matches the subscriber it is currently waiting on. A reply that arrives after its subscriber's timeout carries a now-stale ref and is ignored — it must not cancel or affect any later subscriber.

When a monitored subscriber process goes down (`:DOWN` message), remove all its subscriptions across all topics. If an in-flight publish is waiting on a now-dead subscriber, treat it as `:ack` (continue, don't cancel), count that subscriber as reached, and continue delivery.

A single pid may subscribe to the same topic multiple times at different (or the same) priorities and will receive the event once per subscription, each time with its own `reply_to` ref. Each subscription is independently unsubscribable.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.
