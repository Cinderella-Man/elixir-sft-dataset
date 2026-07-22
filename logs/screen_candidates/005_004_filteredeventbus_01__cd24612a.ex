defmodule FilteredEventBus do
  @moduledoc """
  An in-process publish/subscribe event bus with **content-based routing**.

  Unlike wildcard topic matching, which routes on a single string field, this bus pairs an
  exact topic with an optional declarative *filter* evaluated against the structure of each
  published event. That lets subscribers express interest such as "orders over $1000",
  "errors from region `us-east`", or "any event where the user is an admin" without
  inventing an explosive number of topic names.

  ## Filters

  A filter is a **list of clauses**, all of which must match (implicit AND). An empty list
  matches every event. The supported clauses are:

    * `{:eq, path, value}` — value at `path` equals `value`
    * `{:neq, path, value}` — value at `path` does not equal `value`
    * `{:gt, path, value}` / `{:lt, path, value}` / `{:gte, path, value}` / `{:lte, path, value}`
      — numeric comparison; `false` if either side is not a number
    * `{:in, path, list}` — value at `path` is a member of `list`
    * `{:exists, path}` — `path` resolves to a non-nil value
    * `{:any, [clause, ...]}` — at least one sub-clause matches (OR)
    * `{:none, [clause, ...]}` — no sub-clause matches (NOR)

  Elements of `:any` / `:none` are bare clause tuples; a nested clause *list* is not valid.

  ## Paths

  A `path` is a list of map keys or integer list indices, e.g. `[:user, :role]` reads
  `event[:user][:role]`. Navigation goes through `Access`, and any path that does not
  resolve yields `nil` rather than raising. A `nil` result fails every clause except
  `{:eq, path, nil}` and `{:neq, path, non_nil}`.

  ## Example

      {:ok, bus} = FilteredEventBus.start_link(name: MyBus)

      {:ok, _ref} =
        FilteredEventBus.subscribe(MyBus, "orders", self(), [
          {:gt, [:total], 1000},
          {:any, [{:eq, [:user, :role], :admin}, {:in, [:region], ["us-east", "us-west"]}]}
        ])

      FilteredEventBus.publish(MyBus, "orders", %{total: 2500, region: "us-east"})
      #=> {:ok, 1}

      receive do
        {:event, "orders", event} -> event
      end
  """

  use GenServer

  @comparison_ops [:gt, :lt, :gte, :lte]

  @typedoc "A location inside an event: map keys and/or integer list indices."
  @type path :: [atom() | binary() | integer()]

  @typedoc "A single filter clause."
  @type clause ::
          {:eq, path(), term()}
          | {:neq, path(), term()}
          | {:gt, path(), term()}
          | {:lt, path(), term()}
          | {:gte, path(), term()}
          | {:lte, path(), term()}
          | {:in, path(), list()}
          | {:exists, path()}
          | {:any, [clause()]}
          | {:none, [clause()]}

  @typedoc "A full subscription filter: a list of clauses combined with AND."
  @type filter :: [clause()]

  @typedoc "An event topic. Compared for exact equality; no wildcards."
  @type topic :: term()

  @typedoc "A GenServer reference accepted by the public API."
  @type server :: GenServer.server()

  defmodule Subscription do
    @moduledoc false
    defstruct [:ref, :pid, :topic, :filter]
  end

  defstruct topics: %{}, monitors: %{}

  # ------------------------------------------------------------------
  # Public API
  # ------------------------------------------------------------------

  @doc """
  Starts the event bus.

  Accepts the `:name` option, which is passed through to `GenServer.start_link/3`; all
  other options are ignored.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, _rest} = Keyword.pop(opts, :name)
    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, :ok, server_opts)
  end

  @doc """
  Subscribes `pid` to `topic` (matched by exact equality) with `filter`.

  The subscriber is monitored so that its subscriptions are removed automatically when it
  dies. The same pid may subscribe to the same topic any number of times with different
  filters; each subscription gets its own reference and delivers its own message.

  Returns `{:ok, ref}`, or `{:error, :invalid_filter}` when the filter is structurally
  invalid.
  """
  @spec subscribe(server(), topic(), pid(), filter()) :: {:ok, reference()} | {:error, :invalid_filter}
  def subscribe(server, topic, pid, filter \\ []) when is_pid(pid) do
    if valid_filter?(filter) do
      GenServer.call(server, {:subscribe, topic, pid, filter})
    else
      {:error, :invalid_filter}
    end
  end

  @doc """
  Removes the subscription identified by `ref` from `topic`.

  When the subscriber has no remaining subscriptions on any topic, its monitor is released.
  Unknown topics or refs are ignored. Always returns `:ok`.
  """
  @spec unsubscribe(server(), topic(), reference()) :: :ok
  def unsubscribe(server, topic, ref) when is_reference(ref) do
    GenServer.call(server, {:unsubscribe, topic, ref})
  end

  @doc """
  Publishes `event` on `topic`.

  Every subscriber whose topic matches exactly and whose filter matches `event` receives
  `{:event, topic, event}`. Returns `{:ok, matched_count}` with the number of subscriptions
  that were delivered to.
  """
  @spec publish(server(), topic(), term()) :: {:ok, non_neg_integer()}
  def publish(server, topic, event) do
    GenServer.call(server, {:publish, topic, event})
  end

  @doc """
  Evaluates `filter` against `event` without involving the bus process.

  Useful for subscribers that want to reproduce the bus's routing decision client-side.
  Returns `true`/`false`, or `{:error, :invalid_filter}` when the filter is structurally
  invalid.
  """
  @spec test_filter(filter(), term()) :: boolean() | {:error, :invalid_filter}
  def test_filter(filter, event) do
    if valid_filter?(filter) do
      match_filter?(filter, event)
    else
      {:error, :invalid_filter}
    end
  end

  # ------------------------------------------------------------------
  # GenServer callbacks
  # ------------------------------------------------------------------

  @impl true
  def init(:ok) do
    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_call({:subscribe, topic, pid, filter}, _from, state) do
    ref = make_ref()
    sub = %Subscription{ref: ref, pid: pid, topic: topic, filter: filter}

    subs = Map.get(state.topics, topic, [])
    topics = Map.put(state.topics, topic, subs ++ [sub])
    monitors = ensure_monitor(state.monitors, pid)

    {:reply, {:ok, ref}, %{state | topics: topics, monitors: monitors}}
  end

  def handle_call({:unsubscribe, topic, ref}, _from, state) do
    case Map.fetch(state.topics, topic) do
      {:ok, subs} ->
        {removed, kept} = Enum.split_with(subs, &(&1.ref == ref))

        topics =
          if kept == [] do
            Map.delete(state.topics, topic)
          else
            Map.put(state.topics, topic, kept)
          end

        state = %{state | topics: topics}

        state =
          case removed do
            [%Subscription{pid: pid} | _] -> release_monitor(state, pid)
            [] -> state
          end

        {:reply, :ok, state}

      :error ->
        {:reply, :ok, state}
    end
  end

  def handle_call({:publish, topic, event}, _from, state) do
    matched =
      state.topics
      |> Map.get(topic, [])
      |> Enum.reduce(0, fn sub, count ->
        if match_filter?(sub.filter, event) do
          send(sub.pid, {:event, topic, event})
          count + 1
        else
          count
        end
      end)

    {:reply, {:ok, matched}, state}
  end

  @impl true
  def handle_info({:DOWN, _mref, :process, pid, _reason}, state) do
    topics =
      state.topics
      |> Enum.reduce(%{}, fn {topic, subs}, acc ->
        case Enum.reject(subs, &(&1.pid == pid)) do
          [] -> acc
          kept -> Map.put(acc, topic, kept)
        end
      end)

    {:noreply, %{state | topics: topics, monitors: Map.delete(state.monitors, pid)}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ------------------------------------------------------------------
  # Monitor bookkeeping
  # ------------------------------------------------------------------

  defp ensure_monitor(monitors, pid) do
    case Map.fetch(monitors, pid) do
      {:ok, {mref, count}} -> Map.put(monitors, pid, {mref, count + 1})
      :error -> Map.put(monitors, pid, {Process.monitor(pid), 1})
    end
  end

  defp release_monitor(state, pid) do
    case Map.fetch(state.monitors, pid) do
      {:ok, {mref, 1}} ->
        Process.demonitor(mref, [:flush])
        %{state | monitors: Map.delete(state.monitors, pid)}

      {:ok, {mref, count}} ->
        %{state | monitors: Map.put(state.monitors, pid, {mref, count - 1})}

      :error ->
        state
    end
  end

  # ------------------------------------------------------------------
  # Filter validation (structural only)
  # ------------------------------------------------------------------

  defp valid_filter?(filter) when is_list(filter), do: Enum.all?(filter, &valid_clause?/1)
  defp valid_filter?(_filter), do: false

  defp valid_clause?({:eq, path, _value}), do: valid_path?(path)
  defp valid_clause?({:neq, path, _value}), do: valid_path?(path)
  defp valid_clause?({op, path, _value}) when op in @comparison_ops, do: valid_path?(path)
  defp valid_clause?({:in, path, list}), do: valid_path?(path) and is_list(list)
  defp valid_clause?({:exists, path}), do: valid_path?(path)
  defp valid_clause?({:any, clauses}), do: valid_group?(clauses)
  defp valid_clause?({:none, clauses}), do: valid_group?(clauses)
  defp valid_clause?(_other), do: false

  defp valid_group?(clauses) when is_list(clauses) and clauses != [] do
    Enum.all?(clauses, fn clause -> is_tuple(clause) and valid_clause?(clause) end)
  end

  defp valid_group?(_clauses), do: false

  defp valid_path?(path) when is_list(path) do
    Enum.all?(path, fn segment ->
      is_atom(segment) or is_binary(segment) or is_integer(segment)
    end)
  end

  defp valid_path?(_path), do: false

  # ------------------------------------------------------------------
  # Filter evaluation
  # ------------------------------------------------------------------

  defp match_filter?(filter, event), do: Enum.all?(filter, &match_clause?(&1, event))

  defp match_clause?({:eq, path, value}, event), do: fetch_path(event, path) == value
  defp match_clause?({:neq, path, value}, event), do: fetch_path(event, path) != value

  defp match_clause?({op, path, value}, event) when op in @comparison_ops do
    compare(op, fetch_path(event, path), value)
  end

  defp match_clause?({:in, path, list}, event) do
    value = fetch_path(event, path)
    Enum.any?(list, &(&1 === value or &1 == value))
  end

  defp match_clause?({:exists, path}, event), do: fetch_path(event, path) != nil

  defp match_clause?({:any, clauses}, event) do
    Enum.any?(clauses, &match_clause?(&1, event))
  end

  defp match_clause?({:none, clauses}, event) do
    not Enum.any?(clauses, &match_clause?(&1, event))
  end

  defp compare(op, left, right) when is_number(left) and is_number(right) do
    case op do
      :gt -> left > right
      :lt -> left < right
      :gte -> left >= right
      :lte -> left <= right
    end
  end

  defp compare(_op, _left, _right), do: false

  # ------------------------------------------------------------------
  # Path navigation
  # ------------------------------------------------------------------

  defp fetch_path(event, path), do: Enum.reduce_while(path, event, &step/2)

  defp step(_segment, nil), do: {:halt, nil}

  defp step(index, list) when is_list(list) and is_integer(index) do
    {:cont, Enum.at(list, index)}
  end

  defp step(_segment, list) when is_list(list), do: {:halt, nil}

  defp step(key, %_struct{} = data) when is_atom(key) do
    {:cont, Map.get(data, key)}
  end

  defp step(_key, %_struct{}), do: {:halt, nil}

  defp step(key, %{} = data), do: {:cont, Map.get(data, key)}

  defp step(_segment, _other), do: {:halt, nil}
end