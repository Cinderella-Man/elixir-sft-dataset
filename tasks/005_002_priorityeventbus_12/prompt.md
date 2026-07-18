# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `handle_info` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

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

## The module with `handle_info` missing

```elixir
defmodule PriorityEventBus do
  @moduledoc """
  An in-process pub/sub bus with priority-ordered, serial, cancellable delivery.

  Unlike standard fan-out pub/sub, `publish/3` walks subscribers in descending
  priority order (ties broken by subscription order) and waits for an
  ack or cancel from each before proceeding to the next.  A high-priority
  subscriber can `cancel/1` to veto delivery to all remaining lower-priority
  subscribers — useful for validators, audit gates, and cache-invalidation
  layers that must run before dependent handlers.

  State:

      %{
        # %{topic => [%{ref, pid, priority, seq}, ...]}  (list, kept sorted)
        topics: %{},
        # %{monitor_ref => {pid, [topic, ...]}} — for :DOWN cleanup without
        # scanning every topic
        monitors: %{},
        # Monotonic counter for tie-breaking within a priority level.
        next_seq: 0,
        delivery_timeout_ms: pos_integer
      }

  ## Options

    * `:name`                 – optional process registration
    * `:delivery_timeout_ms`  – max wait per subscriber for ack/cancel
                                (default 5_000)

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

  @spec subscribe(GenServer.server(), String.t(), pid(), integer()) :: {:ok, reference()}
  def subscribe(server, topic, pid, priority)
      when is_binary(topic) and is_pid(pid) and is_integer(priority) do
    GenServer.call(server, {:subscribe, topic, pid, priority})
  end

  @spec unsubscribe(GenServer.server(), String.t(), reference()) :: :ok
  def unsubscribe(server, topic, ref) when is_binary(topic) and is_reference(ref) do
    GenServer.call(server, {:unsubscribe, topic, ref})
  end

  @spec publish(GenServer.server(), String.t(), term()) :: {:ok, non_neg_integer()}
  def publish(server, topic, event) when is_binary(topic) do
    GenServer.call(server, {:publish, topic, event}, :infinity)
  end

  @spec subscribers(GenServer.server(), String.t()) :: [{reference(), pid(), integer()}]
  def subscribers(server, topic) when is_binary(topic) do
    GenServer.call(server, {:subscribers, topic})
  end

  @doc "Convenience: send an ack to the bus using the `reply_to` from an event."
  @spec ack({pid(), reference()}) :: :ok
  def ack({bus_pid, ref}) when is_pid(bus_pid) and is_reference(ref) do
    send(bus_pid, {:ack, ref})
    :ok
  end

  @doc "Convenience: cancel further delivery using the `reply_to` from an event."
  @spec cancel({pid(), reference()}) :: :ok
  def cancel({bus_pid, ref}) when is_pid(bus_pid) and is_reference(ref) do
    send(bus_pid, {:cancel, ref})
    :ok
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(opts) do
    {:ok,
     %{
       topics: %{},
       monitors: %{},
       next_seq: 0,
       delivery_timeout_ms: Keyword.get(opts, :delivery_timeout_ms, 5_000)
     }}
  end

  @impl true
  def handle_call({:subscribe, topic, pid, priority}, _from, state) do
    ref = Process.monitor(pid)
    seq = state.next_seq

    sub = %{ref: ref, pid: pid, priority: priority, seq: seq}

    existing = Map.get(state.topics, topic, []) |> without(ref)
    new_subs_for_topic = insert_sorted([sub | existing], sub)

    monitors =
      Map.update(state.monitors, ref, {pid, [topic]}, fn {p, topics} ->
        {p, Enum.uniq([topic | topics])}
      end)

    new_state = %{
      state
      | topics: Map.put(state.topics, topic, new_subs_for_topic),
        monitors: monitors,
        next_seq: seq + 1
    }

    {:reply, {:ok, ref}, new_state}
  end

  def handle_call({:unsubscribe, topic, ref}, _from, state) do
    new_state = remove_ref_from_topic(state, topic, ref)
    {:reply, :ok, new_state}
  end

  def handle_call({:subscribers, topic}, _from, state) do
    list =
      state.topics
      |> Map.get(topic, [])
      |> Enum.map(fn %{ref: r, pid: p, priority: pri} -> {r, p, pri} end)

    {:reply, list, state}
  end

  def handle_call({:publish, topic, event}, _from, state) do
    subs = Map.get(state.topics, topic, [])
    delivered = deliver_serially(subs, topic, event, state.delivery_timeout_ms, 0)
    {:reply, {:ok, delivered}, state}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    # TODO
  end

  # ---------------------------------------------------------------------------
  # Serial delivery with ack/cancel — the core of this module
  # ---------------------------------------------------------------------------

  # Walks the list in order.  For each subscriber:
  #   - Send {:event, topic, event, {self(), unique_ref}}
  #   - Receive {:ack, unique_ref} | {:cancel, unique_ref} | timeout | :DOWN
  #   - :ack / timeout / :DOWN continue; :cancel stops delivery.
  defp deliver_serially([], _topic, _event, _timeout, delivered), do: delivered

  defp deliver_serially([sub | rest], topic, event, timeout, delivered) do
    unique_ref = make_ref()
    reply_to = {self(), unique_ref}

    send(sub.pid, {:event, topic, event, reply_to})

    receive do
      {:ack, ^unique_ref} ->
        deliver_serially(rest, topic, event, timeout, delivered + 1)

      {:cancel, ^unique_ref} ->
        delivered + 1

      # If the subscriber dies mid-publish, its monitor fires; treat as :ack
      # and continue.  We don't consume the :DOWN here — we leave it for
      # the regular handle_info path so the cleanup still runs.
      {:DOWN, _ref, :process, pid, _reason} = down when pid == sub.pid ->
        # Re-queue for normal processing and continue.
        send(self(), down)
        deliver_serially(rest, topic, event, timeout, delivered + 1)
    after
      timeout ->
        deliver_serially(rest, topic, event, timeout, delivered + 1)
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  # Sorted insert: descending priority, then ascending subscription order (seq).
  defp insert_sorted(list, sub) do
    # `list` already has `sub` filtered out (see caller).  Prepend and sort —
    # the list is typically small so this is fine.
    [sub | list]
    |> Enum.uniq_by(& &1.ref)
    |> Enum.sort_by(fn %{priority: p, seq: s} -> {-p, s} end)
  end

  defp without(list, ref), do: Enum.reject(list, &(&1.ref == ref))

  defp remove_ref_from_topic(state, topic, ref) do
    case Map.get(state.topics, topic) do
      nil ->
        state

      subs ->
        new_subs = without(subs, ref)
        topics = Map.put(state.topics, topic, new_subs)

        # Update monitors map: drop topic from this ref's list; demonitor
        # if no topics remain.
        monitors =
          case Map.fetch(state.monitors, ref) do
            {:ok, {pid, topics_list}} ->
              remaining = List.delete(topics_list, topic)

              if remaining == [] do
                Process.demonitor(ref, [:flush])
                Map.delete(state.monitors, ref)
              else
                Map.put(state.monitors, ref, {pid, remaining})
              end

            :error ->
              state.monitors
          end

        %{state | topics: topics, monitors: monitors}
    end
  end
end
```

Give me only the complete implementation of `handle_info` (including the
`@doc`/`@spec`/`@impl` lines shown above it in the module, if any) — the
function alone, not the whole module.
