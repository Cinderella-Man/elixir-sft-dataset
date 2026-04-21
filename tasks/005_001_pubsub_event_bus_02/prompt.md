Implement the private `topic_matches?/2` function. It should determine if a given `pattern` (which may contain wildcards) matches a specific `topic`. 

First, split both the `pattern` and the `topic` into segments using the `.` delimiter. A match is only possible if both have the same number of segments. If the lengths match, delegate the segment-by-segment comparison to `segments_match?/2`. Return a boolean.

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
    # TODO
  end

  defp segments_match?([], []), do: true
  defp segments_match?(["*" | pr], [_ | tr]), do: segments_match?(pr, tr)
  defp segments_match?([s | pr], [s | tr]), do: segments_match?(pr, tr)
  defp segments_match?(_, _), do: false
end
```