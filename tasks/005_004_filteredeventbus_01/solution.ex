defmodule FilteredEventBus do
  @moduledoc """
  An in-process pub/sub bus with content-based filter subscriptions.

  Replaces wildcard topic matching with a small, evaluable match-spec DSL
  stored per subscription.  Each subscription carries a list of clauses
  (implicit AND); an event is delivered only when every clause matches.

  Supported clauses:

      {:eq, path, value}                   – event[path] == value
      {:neq, path, value}                  – event[path] != value
      {:gt | :lt | :gte | :lte, path, v}   – numeric comparisons
      {:in, path, list}                    – event[path] ∈ list
      {:exists, path}                      – event[path] is not nil
      {:any, [clause, ...]}                – at least one sub-clause matches
      {:none, [clause, ...]}               – no sub-clause matches

  `path` is a list of map keys or integer list indices.  A path that fails to
  resolve yields `nil` (never raises); most clauses fail against `nil`.

  State:

      %{
        topics: %{topic => [%{ref, pid, filter}, ...]},
        monitors: %{ref => {pid, [topic, ...]}}
      }

  ## Options

    * `:name` – optional process registration

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

  @spec subscribe(GenServer.server(), String.t(), pid(), list()) ::
          {:ok, reference()} | {:error, :invalid_filter}
  def subscribe(server, topic, pid, filter \\ [])
      when is_binary(topic) and is_pid(pid) and is_list(filter) do
    if valid_filter?(filter) do
      GenServer.call(server, {:subscribe, topic, pid, filter})
    else
      {:error, :invalid_filter}
    end
  end

  @spec unsubscribe(GenServer.server(), String.t(), reference()) :: :ok
  def unsubscribe(server, topic, ref), do: GenServer.call(server, {:unsubscribe, topic, ref})

  @spec publish(GenServer.server(), String.t(), term()) :: {:ok, non_neg_integer()}
  def publish(server, topic, event) when is_binary(topic) do
    GenServer.call(server, {:publish, topic, event})
  end

  @doc """
  Pure evaluation of `filter` against `event`, outside any GenServer.
  Returns `true | false`, or `{:error, :invalid_filter}` if the filter fails
  structural validation.
  """
  @spec test_filter(list(), term()) :: boolean() | {:error, :invalid_filter}
  def test_filter(filter, event) when is_list(filter) do
    if valid_filter?(filter) do
      eval_filter(filter, event)
    else
      {:error, :invalid_filter}
    end
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(_opts) do
    {:ok, %{topics: %{}, monitors: %{}}}
  end

  @impl true
  def handle_call({:subscribe, topic, pid, filter}, _from, state) do
    ref = Process.monitor(pid)
    sub = %{ref: ref, pid: pid, filter: filter}

    subs_for_topic = Map.get(state.topics, topic, []) ++ [sub]

    monitors =
      Map.update(state.monitors, ref, {pid, [topic]}, fn {p, topics} ->
        {p, Enum.uniq([topic | topics])}
      end)

    {:reply, {:ok, ref},
     %{state | topics: Map.put(state.topics, topic, subs_for_topic), monitors: monitors}}
  end

  def handle_call({:unsubscribe, topic, ref}, _from, state) do
    {:reply, :ok, remove_ref_from_topic(state, topic, ref)}
  end

  def handle_call({:publish, topic, event}, _from, state) do
    subs = Map.get(state.topics, topic, [])

    matched =
      Enum.reduce(subs, 0, fn sub, acc ->
        if eval_filter(sub.filter, event) do
          send(sub.pid, {:event, topic, event})
          acc + 1
        else
          acc
        end
      end)

    {:reply, {:ok, matched}, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case Map.pop(state.monitors, ref) do
      {nil, _} ->
        {:noreply, state}

      {{_pid, topics}, monitors} ->
        new_topics =
          Enum.reduce(topics, state.topics, fn topic, acc ->
            case Map.get(acc, topic) do
              nil -> acc
              subs -> Map.put(acc, topic, Enum.reject(subs, &(&1.ref == ref)))
            end
          end)

        {:noreply, %{state | topics: new_topics, monitors: monitors}}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Filter validation
  # ---------------------------------------------------------------------------

  defp valid_filter?(filter) when is_list(filter) do
    Enum.all?(filter, &valid_clause?/1)
  end

  defp valid_filter?(_), do: false

  defp valid_clause?({op, path, _val})
       when op in [:eq, :neq, :gt, :lt, :gte, :lte] and is_list(path) do
    valid_path?(path)
  end

  defp valid_clause?({:in, path, list}) when is_list(path) and is_list(list) do
    valid_path?(path)
  end

  defp valid_clause?({:exists, path}) when is_list(path), do: valid_path?(path)

  defp valid_clause?({:any, subs}) when is_list(subs) and subs != [] do
    Enum.all?(subs, &valid_clause?/1)
  end

  defp valid_clause?({:none, subs}) when is_list(subs) and subs != [] do
    Enum.all?(subs, &valid_clause?/1)
  end

  defp valid_clause?(_), do: false

  defp valid_path?(path) do
    Enum.all?(path, fn
      k when is_atom(k) or is_binary(k) or is_integer(k) -> true
      _ -> false
    end)
  end

  # ---------------------------------------------------------------------------
  # Filter evaluation
  # ---------------------------------------------------------------------------

  # Top-level filter: list of clauses, all must match.
  defp eval_filter(filter, event) do
    Enum.all?(filter, &eval_clause(&1, event))
  end

  defp eval_clause({:eq, path, value}, event), do: fetch(event, path) == value
  defp eval_clause({:neq, path, value}, event), do: fetch(event, path) != value

  defp eval_clause({:gt, path, value}, event), do: num_cmp(fetch(event, path), value, &>/2)
  defp eval_clause({:lt, path, value}, event), do: num_cmp(fetch(event, path), value, &</2)
  defp eval_clause({:gte, path, value}, event), do: num_cmp(fetch(event, path), value, &>=/2)
  defp eval_clause({:lte, path, value}, event), do: num_cmp(fetch(event, path), value, &<=/2)

  defp eval_clause({:in, path, list}, event), do: fetch(event, path) in list

  defp eval_clause({:exists, path}, event), do: fetch(event, path) != nil

  defp eval_clause({:any, subs}, event), do: Enum.any?(subs, &eval_clause(&1, event))

  defp eval_clause({:none, subs}, event), do: not Enum.any?(subs, &eval_clause(&1, event))

  # Numeric comparison that returns false for non-numeric operands (including nil).
  defp num_cmp(a, b, op) when is_number(a) and is_number(b), do: op.(a, b)
  defp num_cmp(_, _, _), do: false

  # Path navigation: maps by key, lists by integer index.  Missing keys → nil.
  defp fetch(value, []), do: value

  defp fetch(map, [key | rest]) when is_map(map) do
    case Map.fetch(map, key) do
      {:ok, v} -> fetch(v, rest)
      :error -> nil
    end
  end

  defp fetch(list, [idx | rest]) when is_list(list) and is_integer(idx) do
    case Enum.at(list, idx, :__missing__) do
      :__missing__ -> nil
      v -> fetch(v, rest)
    end
  end

  defp fetch(_, _), do: nil

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp remove_ref_from_topic(state, topic, ref) do
    case Map.get(state.topics, topic) do
      nil ->
        state

      subs ->
        new_subs = Enum.reject(subs, &(&1.ref == ref))
        topics = Map.put(state.topics, topic, new_subs)

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
