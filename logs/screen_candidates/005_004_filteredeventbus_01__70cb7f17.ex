defmodule FilteredEventBus do
  @moduledoc """
  An in-process publish/subscribe event bus with **content-based routing**.

  Unlike wildcard topic buses, which can only route on a single string field,
  `FilteredEventBus` pairs an *exact* topic with an optional structural
  **filter** evaluated against the published event. Subscribers can therefore
  express interest such as "orders over $1000", "errors from region us-east",
  or "any event whose user is an admin" without inventing a combinatorial
  explosion of topic names.

  ## Filters

  A filter is a **list of clauses**, all of which must match (implicit AND).
  The empty list `[]` always matches.

  Supported clauses:

    * `{:eq, path, value}` — value at `path` equals `value`
    * `{:neq, path, value}` — value at `path` does not equal `value`
    * `{:gt, path, value}` — numeric `>` (false if either side is non-numeric)
    * `{:lt, path, value}` — numeric `<` (false if either side is non-numeric)
    * `{:gte, path, value}` — numeric `>=` (false if either side is non-numeric)
    * `{:lte, path, value}` — numeric `<=` (false if either side is non-numeric)
    * `{:in, path, list}` — value at `path` is a member of `list`
    * `{:exists, path}` — `path` resolves to a non-nil value
    * `{:any, [clause_or_filter, ...]}` — at least one sub-filter matches (OR)
    * `{:none, [clause_or_filter, ...]}` — no sub-filter matches (NOR)

  A `path` is a list of map keys or integer list indices, e.g. `[:user, :role]`
  navigates `event[:user][:role]`. Navigation never raises: an unresolvable path
  yields `nil`, which fails every clause except `{:eq, path, nil}` and
  `{:neq, path, non_nil}`.

  Filters are pure data — they are validated *structurally* at subscription time
  and interpreted at publish time. No `eval`, no closures stored in state.

  ## Example

      {:ok, bus} = FilteredEventBus.start_link(name: :bus)

      {:ok, _ref} =
        FilteredEventBus.subscribe(:bus, "orders", self(), [
          {:gt, [:total], 1000},
          {:any, [{:eq, [:user, :role], :admin}, {:eq, [:priority], :high}]}
        ])

      FilteredEventBus.publish(:bus, "orders", %{total: 2500, priority: :high})
      #=> {:ok, 1}

      receive do
        {:event, "orders", event} -> event
      end
  """

  use GenServer

  @typedoc "A navigation path into an event: map keys and/or list indices."
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

  @typedoc "A filter: a list of clauses combined with AND. `[]` always matches."
  @type filter :: [clause()]

  @typedoc "An opaque subscription reference."
  @type subscription_ref :: reference()

  @typedoc "A topic. Matched exactly — no wildcards."
  @type topic :: term()

  @typedoc "A published event. Typically a map or struct."
  @type event :: term()

  @comparison_ops [:gt, :lt, :gte, :lte]

  # A subscription record held in state.
  defmodule Subscription do
    @moduledoc false
    @enforce_keys [:ref, :pid, :topic, :filter]
    defstruct [:ref, :pid, :topic, :filter]
  end

  # State:
  #   topics:   %{topic => [%Subscription{}]}  (reverse insertion order internally)
  #   monitors: %{pid => {monitor_ref, subscription_count}}
  defstruct topics: %{}, monitors: %{}

  ## ------------------------------------------------------------------
  ## Public API
  ## ------------------------------------------------------------------

  @doc """
  Starts the event bus.

  Accepts the `:name` option, which is passed straight through to `GenServer`
  registration; any other options are forwarded to `GenServer.start_link/3`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)
    server_opts = if name, do: [name: name] ++ opts, else: opts
    GenServer.start_link(__MODULE__, :ok, server_opts)
  end

  @doc """
  Subscribes `pid` to `topic` with an optional content-based `filter`.

  The topic is matched *exactly* — there is no wildcard support. The filter is a
  list of clauses, all of which must match a published event for it to be
  delivered; the default `[]` matches every event on the topic.

  The bus monitors `pid`, and drops all of its subscriptions if it dies.

  The same pid may subscribe to the same topic multiple times with different
  filters; each subscription gets its own ref, is independently unsubscribable,
  and produces its own delivery.

  Returns `{:ok, ref}`, or `{:error, :invalid_filter}` when the filter fails
  structural validation.
  """
  @spec subscribe(GenServer.server(), topic(), pid(), filter()) ::
          {:ok, subscription_ref()} | {:error, :invalid_filter}
  def subscribe(server, topic, pid, filter \\ []) when is_pid(pid) do
    if valid_filter?(filter) do
      GenServer.call(server, {:subscribe, topic, pid, filter})
    else
      {:error, :invalid_filter}
    end
  end

  @doc """
  Removes the subscription identified by `ref` from `topic`.

  Demonitors the subscriber once its last subscription across all topics has
  been removed. Always returns `:ok`, even when the subscription is unknown.
  """
  @spec unsubscribe(GenServer.server(), topic(), subscription_ref()) :: :ok
  def unsubscribe(server, topic, ref) when is_reference(ref) do
    GenServer.call(server, {:unsubscribe, topic, ref})
  end

  @doc """
  Publishes `event` on `topic`.

  Every subscriber whose topic matches exactly *and* whose filter matches the
  event receives the message `{:event, topic, event}`. A pid with several
  matching subscriptions on the topic receives one message per subscription.

  Returns `{:ok, matched_count}` — the number of subscriptions that were
  delivered to.
  """
  @spec publish(GenServer.server(), topic(), event()) :: {:ok, non_neg_integer()}
  def publish(server, topic, event) do
    GenServer.call(server, {:publish, topic, event})
  end

  @doc """
  Evaluates `filter` against `event` without touching the bus.

  This is the exact predicate the bus uses to route events, exposed so that
  subscribers can replicate routing decisions client-side.

  Returns `true` or `false`, or `{:error, :invalid_filter}` when the filter
  fails structural validation.
  """
  @spec test_filter(filter(), event()) :: boolean() | {:error, :invalid_filter}
  def test_filter(filter, event) do
    if valid_filter?(filter) do
      match_filter?(filter, event)
    else
      {:error, :invalid_filter}
    end
  end

  ## ------------------------------------------------------------------
  ## GenServer callbacks
  ## ------------------------------------------------------------------

  @impl GenServer
  def init(:ok) do
    {:ok, %__MODULE__{}}
  end

  @impl GenServer
  def handle_call({:subscribe, topic, pid, filter}, _from, state) do
    ref = make_ref()
    sub = %Subscription{ref: ref, pid: pid, topic: topic, filter: filter}

    subs = Map.get(state.topics, topic, [])
    topics = Map.put(state.topics, topic, [sub | subs])

    {:reply, {:ok, ref}, %{state | topics: topics, monitors: add_monitor(state.monitors, pid)}}
  end

  def handle_call({:unsubscribe, topic, ref}, _from, state) do
    subs = Map.get(state.topics, topic, [])

    case Enum.split_with(subs, &(&1.ref == ref)) do
      {[], _rest} ->
        {:reply, :ok, state}

      {[removed | _], rest} ->
        topics =
          if rest == [] do
            Map.delete(state.topics, topic)
          else
            Map.put(state.topics, topic, rest)
          end

        monitors = drop_monitor(state.monitors, removed.pid)
        {:reply, :ok, %{state | topics: topics, monitors: monitors}}
    end
  end

  def handle_call({:publish, topic, event}, _from, state) do
    matched =
      state.topics
      |> Map.get(topic, [])
      |> Enum.reverse()
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

  @impl GenServer
  def handle_info({:DOWN, _mon_ref, :process, pid, _reason}, state) do
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

  ## ------------------------------------------------------------------
  ## Monitor bookkeeping
  ## ------------------------------------------------------------------

  defp add_monitor(monitors, pid) do
    case Map.fetch(monitors, pid) do
      {:ok, {mon_ref, count}} -> Map.put(monitors, pid, {mon_ref, count + 1})
      :error -> Map.put(monitors, pid, {Process.monitor(pid), 1})
    end
  end

  defp drop_monitor(monitors, pid) do
    case Map.fetch(monitors, pid) do
      {:ok, {mon_ref, count}} when count <= 1 ->
        Process.demonitor(mon_ref, [:flush])
        Map.delete(monitors, pid)

      {:ok, {mon_ref, count}} ->
        Map.put(monitors, pid, {mon_ref, count - 1})

      :error ->
        monitors
    end
  end

  ## ------------------------------------------------------------------
  ## Filter validation (structural only)
  ## ------------------------------------------------------------------

  defp valid_filter?(clauses) when is_list(clauses), do: Enum.all?(clauses, &valid_clause?/1)
  defp valid_filter?(_other), do: false

  defp valid_clause?({op, path, _value}) when op in [:eq, :neq], do: valid_path?(path)

  defp valid_clause?({op, path, _value}) when op in @comparison_ops, do: valid_path?(path)

  defp valid_clause?({:in, path, list}) when is_list(list), do: valid_path?(path)

  defp valid_clause?({:exists, path}), do: valid_path?(path)

  defp valid_clause?({op, subfilters}) when op in [:any, :none] and is_list(subfilters) do
    subfilters != [] and Enum.all?(subfilters, &valid_subfilter?/1)
  end

  defp valid_clause?(_other), do: false

  # A member of an :any/:none group may be a single clause or a nested
  # AND-group expressed as a list of clauses.
  defp valid_subfilter?(list) when is_list(list), do: valid_filter?(list)
  defp valid_subfilter?(clause), do: valid_clause?(clause)

  defp valid_path?(path) when is_list(path), do: Enum.all?(path, &valid_path_segment?/1)
  defp valid_path?(_other), do: false

  defp valid_path_segment?(seg) when is_atom(seg) or is_binary(seg) or is_integer(seg), do: true
  defp valid_path_segment?(_seg), do: false

  ## ------------------------------------------------------------------
  ## Filter evaluation
  ## ------------------------------------------------------------------

  defp match_filter?(clauses, event) when is_list(clauses) do
    Enum.all?(clauses, &match_clause?(&1, event))
  end

  defp match_clause?({:eq, path, value}, event), do: fetch_path(event, path) == value
  defp match_clause?({:neq, path, value}, event), do: fetch_path(event, path) != value

  defp match_clause?({op, path, value}, event) when op in @comparison_ops do
    compare(op, fetch_path(event, path), value)
  end

  defp match_clause?({:in, path, list}, event) when is_list(list) do
    event |> fetch_path(path) |> Kernel.in(list)
  end

  defp match_clause?({:exists, path}, event), do: fetch_path(event, path) != nil

  defp match_clause?({:any, subfilters}, event) do
    Enum.any?(subfilters, &match_subfilter?(&1, event))
  end

  defp match_clause?({:none, subfilters}, event) do
    not Enum.any?(subfilters, &match_subfilter?(&1, event))
  end

  defp match_clause?(_clause, _event), do: false

  defp match_subfilter?(list, event) when is_list(list), do: match_filter?(list, event)
  defp match_subfilter?(clause, event), do: match_clause?(clause, event)

  defp compare(op, left, right) when is_number(left) and is_number(right) do
    case op do
      :gt -> left > right
      :lt -> left < right
      :gte -> left >= right
      :lte -> left <= right
    end
  end

  defp compare(_op, _left, _right), do: false

  ## ------------------------------------------------------------------
  ## Path navigation — never raises, unresolvable paths yield nil
  ## ------------------------------------------------------------------

  defp fetch_path(value, []), do: value

  defp fetch_path(container, [segment | rest]) do
    container
    |> fetch_segment(segment)
    |> fetch_path(rest)
  end

  defp fetch_segment(nil, _segment), do: nil

  defp fetch_segment(container, index) when is_map(container) and is_integer(index) do
    # Integer keys are legitimate map keys; prefer them over list semantics.
    Map.get(container, index)
  end

  defp fetch_segment(container, key) when is_map(container), do: Map.get(container, key)

  defp fetch_segment(container, index) when is_list(container) and is_integer(index) do
    if index >= 0 do
      Enum.at(container, index)
    else
      # Negative indices count from the end, mirroring Enum.at/2.
      Enum.at(container, index)
    end
  end

  defp fetch_segment(container, key) when is_list(container) do
    if Keyword.keyword?(container) and is_atom(key) do
      Keyword.get(container, key)
    else
      nil
    end
  end

  defp fetch_segment(_container, _segment), do: nil
end