Implement the private `deliver_serially/5` function. This function is responsible for the core serial delivery logic of the bus. 

It should iterate through a list of subscribers. For each subscriber:
1. Generate a **unique reference** and construct a `reply_to` tuple containing the bus's PID and that reference.
2. Send an `{:event, topic, event, reply_to}` message to the subscriber's PID.
3. Wait for a response using a `receive` block with a timeout:
    * **If `{:ack, ^unique_ref}` is received:** Increment the delivered count and continue to the next subscriber.
    * **If `{:cancel, ^unique_ref}` is received:** Stop delivery immediately and return the count of subscribers reached (including the current one).
    * **If a `:DOWN` message is received** for the current subscriber's PID: Re-send the message to `self()` (to ensure the GenServer's `handle_info` performs the final cleanup), treat it as an implicit `:ack`, and continue.
    * **On timeout:** Treat it as an implicit `:ack` and continue.

If the subscriber list is empty, return the total `delivered` count.

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

    new_subs_for_topic = insert_sorted([sub | Map.get(state.topics, topic, []) |> without(ref)], sub)

    monitors = Map.update(state.monitors, ref, {pid, [topic]}, fn {p, topics} ->
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

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case Map.pop(state.monitors, ref) do
      {nil, _} ->
        {:noreply, state}

      {{_pid, topics}, monitors} ->
        # For a DOWN, remove this ref from every topic it was subscribed to.
        topics_map =
          Enum.reduce(topics, state.topics, fn topic, acc ->
            case Map.get(acc, topic) do
              nil -> acc
              subs -> Map.put(acc, topic, without(subs, ref))
            end
          end)

        {:noreply, %{state | topics: topics_map, monitors: monitors}}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Serial delivery with ack/cancel — the core of this module
  # ---------------------------------------------------------------------------

  # Walks the list in order.  For each subscriber:
  #   - Send {:event, topic, event, {self(), unique_ref}}
  #   - Receive {:ack, unique_ref} | {:cancel, unique_ref} | timeout | :DOWN
  #   - :ack / timeout / :DOWN continue; :cancel stops delivery.
  # TODO defp deliver_serially

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