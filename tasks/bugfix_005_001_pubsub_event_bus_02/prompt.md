# One bug. Find it. Fix it.

The module below implements the task that follows, except for a single
behavior bug. The bottom of this prompt shows the real failure report from
its (hidden) test suite. Deliver the full corrected module: smallest
possible change, no restructuring, nothing else touched.

## Target behavior

# EventBus: In-Process Pub/Sub Event System — Specification

## Overview

This document specifies an Elixir GenServer module named `EventBus` that implements an in-process publish/subscribe event system with wildcard topic support. The complete module is to be delivered in a single file. It must rely only on the OTP standard library, with no external dependencies.

## API

The module must expose the following public functions:

- `EventBus.start_link(opts)` starts the process. It accepts a `:name` option for process registration.

- `EventBus.subscribe(server, topic, pid)` subscribes the given pid to a topic. The EventBus must automatically `Process.monitor` the subscriber so that dead processes get cleaned up. It returns `{:ok, ref}`, where `ref` is the monitor reference, which also serves as the subscription identifier.

- `EventBus.unsubscribe(server, topic, ref)` removes the subscription identified by `ref` from the given topic. It demonitors the process when its last subscription is removed. It returns `:ok`.

- `EventBus.publish(server, topic, event)` sends `{:event, topic, event}` to every pid subscribed to a matching topic. A subscription matches if the subscribed topic is exactly equal to the published topic, OR if the subscribed topic is a wildcard pattern. It returns `:ok`.

## Wildcard Matching

Wildcard matching follows these rules. A `"*"` segment matches exactly one segment. Segments are separated by `"."`. For example, `"orders.*"` matches `"orders.created"` and `"orders.updated"` but does not match `"orders.items.created"` and does not match `"orders"`. The pattern `"*.*"` matches any two-segment topic. A literal topic such as `"orders.created"` only matches exactly `"orders.created"`.

## Edge cases

When a monitored subscriber process goes down (that is, when the GenServer receives a `:DOWN` message), all of that process's subscriptions across all topics must be automatically removed. If that was the last subscription being monitored for that process, no further cleanup is needed, since the monitor fires only once.

A single pid may subscribe to the same topic multiple times, and it should receive the event once per subscription. Each subscription is independently unsubscribable via its own ref.

## The buggy module

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

  defp segments_match?([], []), do: false
  defp segments_match?(["*" | pr], [_ | tr]), do: segments_match?(pr, tr)
  defp segments_match?([s | pr], [s | tr]), do: segments_match?(pr, tr)
  defp segments_match?(_, _), do: false
end
```

## Failing test report

```
12 of 18 test(s) failed:

  * test subscriber receives published event
      
      
      Assertion failed, no matching message after 500ms
           The process mailbox is empty.
      code: assert_receive {:event, "orders.created", %{id: 1}}
      

  * test multiple subscribers all receive the event
      
      
      Assertion failed, no matching message after 500ms
           The process mailbox is empty.
      code: assert_receive {:sub1, {:event, "topic.a", :hello}}
      

  * test wildcard * matches a single segment
      
      
      Assertion failed, no matching message after 500ms
           The process mailbox is empty.
      code: assert_receive {:event, "orders.created", :e1}
      

  * test *.* matches any two-segment topic
      
      
      Assertion failed, no matching message after 500ms
           The process mailbox is empty.
      code: assert_receive {:event, "orders.created", :e1}
      

  (…8 more)
```
