# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
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
```

## Test harness — implement the `# TODO` test

```elixir
defmodule FilteredEventBusTest do
  use ExUnit.Case, async: false

  setup do
    {:ok, bus} = FilteredEventBus.start_link([])
    %{bus: bus}
  end

  defp drain(topic, timeout \\ 50) do
    drain_loop(topic, [], timeout)
  end

  defp drain_loop(topic, acc, timeout) do
    receive do
      {:event, ^topic, evt} -> drain_loop(topic, [evt | acc], timeout)
    after
      timeout -> Enum.reverse(acc)
    end
  end

  # -------------------------------------------------------
  # Empty filter matches every event
  # -------------------------------------------------------

  test "empty filter matches every event on the topic", %{bus: bus} do
    {:ok, _ref} = FilteredEventBus.subscribe(bus, "t", self())

    FilteredEventBus.publish(bus, "t", %{a: 1})
    FilteredEventBus.publish(bus, "t", %{a: 2})

    assert [%{a: 1}, %{a: 2}] = drain("t")
  end

  test "exact-topic matching only (no wildcards)", %{bus: bus} do
    {:ok, _} = FilteredEventBus.subscribe(bus, "orders.created", self())
    FilteredEventBus.publish(bus, "orders.updated", %{})

    assert [] = drain("orders.updated")
  end

  # -------------------------------------------------------
  # :eq / :neq
  # -------------------------------------------------------

  test ":eq clause filters on nested path", %{bus: bus} do
    {:ok, _} = FilteredEventBus.subscribe(bus, "t", self(), [{:eq, [:user, :role], :admin}])

    FilteredEventBus.publish(bus, "t", %{user: %{role: :admin}})
    FilteredEventBus.publish(bus, "t", %{user: %{role: :guest}})
    FilteredEventBus.publish(bus, "t", %{user: %{role: :admin}, extra: 1})

    assert [
             %{user: %{role: :admin}},
             %{user: %{role: :admin}, extra: 1}
           ] = drain("t")
  end

  test ":neq clause", %{bus: bus} do
    {:ok, _} = FilteredEventBus.subscribe(bus, "t", self(), [{:neq, [:status], :ignored}])

    FilteredEventBus.publish(bus, "t", %{status: :ok})
    FilteredEventBus.publish(bus, "t", %{status: :ignored})

    assert [%{status: :ok}] = drain("t")
  end

  # -------------------------------------------------------
  # Numeric comparisons
  # -------------------------------------------------------

  test ":gt / :gte / :lt / :lte clauses", %{bus: bus} do
    {:ok, _} = FilteredEventBus.subscribe(bus, "t", self(), [{:gt, [:amount], 1000}])

    for a <- [500, 1000, 1001, 5000], do: FilteredEventBus.publish(bus, "t", %{amount: a})

    assert [%{amount: 1001}, %{amount: 5000}] = drain("t")
  end

  test "numeric clauses return false for non-numeric or missing values", %{bus: bus} do
    {:ok, _} = FilteredEventBus.subscribe(bus, "t", self(), [{:gt, [:n], 0}])

    FilteredEventBus.publish(bus, "t", %{n: 5})
    FilteredEventBus.publish(bus, "t", %{n: "five"})
    FilteredEventBus.publish(bus, "t", %{n: nil})
    FilteredEventBus.publish(bus, "t", %{other: 1})

    assert [%{n: 5}] = drain("t")
  end

  # -------------------------------------------------------
  # :in / :exists
  # -------------------------------------------------------

  test ":in clause", %{bus: bus} do
    {:ok, _} =
      FilteredEventBus.subscribe(bus, "t", self(), [{:in, [:region], [:us_east, :us_west]}])

    FilteredEventBus.publish(bus, "t", %{region: :us_east})
    FilteredEventBus.publish(bus, "t", %{region: :eu})
    FilteredEventBus.publish(bus, "t", %{region: :us_west})

    assert [%{region: :us_east}, %{region: :us_west}] = drain("t")
  end

  test ":exists clause", %{bus: bus} do
    # TODO
  end

  # -------------------------------------------------------
  # Top-level AND of clauses
  # -------------------------------------------------------

  test "multiple clauses at top level are AND-ed", %{bus: bus} do
    filter = [
      {:eq, [:type], :purchase},
      {:gt, [:amount], 100}
    ]

    {:ok, _} = FilteredEventBus.subscribe(bus, "t", self(), filter)

    FilteredEventBus.publish(bus, "t", %{type: :purchase, amount: 50})
    FilteredEventBus.publish(bus, "t", %{type: :refund, amount: 500})
    FilteredEventBus.publish(bus, "t", %{type: :purchase, amount: 500})

    assert [%{type: :purchase, amount: 500}] = drain("t")
  end

  # -------------------------------------------------------
  # :any (OR) / :none (NOT-OR)
  # -------------------------------------------------------

  test ":any clause is OR", %{bus: bus} do
    filter = [
      {:any,
       [
         {:eq, [:severity], :critical},
         {:eq, [:severity], :error}
       ]}
    ]

    {:ok, _} = FilteredEventBus.subscribe(bus, "t", self(), filter)

    FilteredEventBus.publish(bus, "t", %{severity: :info})
    FilteredEventBus.publish(bus, "t", %{severity: :error})
    FilteredEventBus.publish(bus, "t", %{severity: :critical})
    FilteredEventBus.publish(bus, "t", %{severity: :warn})

    assert [%{severity: :error}, %{severity: :critical}] = drain("t")
  end

  test ":none clause excludes matching events", %{bus: bus} do
    filter = [
      {:none,
       [
         {:eq, [:source], :internal},
         {:eq, [:source], :debug}
       ]}
    ]

    {:ok, _} = FilteredEventBus.subscribe(bus, "t", self(), filter)

    FilteredEventBus.publish(bus, "t", %{source: :user})
    FilteredEventBus.publish(bus, "t", %{source: :internal})
    FilteredEventBus.publish(bus, "t", %{source: :debug})
    FilteredEventBus.publish(bus, "t", %{source: :api})

    assert [%{source: :user}, %{source: :api}] = drain("t")
  end

  test "combined AND of top-level with nested :any", %{bus: bus} do
    filter = [
      {:eq, [:type], :alert},
      {:any, [{:eq, [:level], :high}, {:eq, [:level], :critical}]}
    ]

    {:ok, _} = FilteredEventBus.subscribe(bus, "t", self(), filter)

    FilteredEventBus.publish(bus, "t", %{type: :alert, level: :low})
    FilteredEventBus.publish(bus, "t", %{type: :alert, level: :high})
    FilteredEventBus.publish(bus, "t", %{type: :note, level: :critical})

    assert [%{type: :alert, level: :high}] = drain("t")
  end

  # -------------------------------------------------------
  # Missing paths
  # -------------------------------------------------------

  test "deeply nested missing path returns nil, not crash", %{bus: bus} do
    {:ok, _} = FilteredEventBus.subscribe(bus, "t", self(), [{:eq, [:a, :b, :c], :x}])

    # No crash, no match
    assert {:ok, 0} = FilteredEventBus.publish(bus, "t", %{})
    assert {:ok, 0} = FilteredEventBus.publish(bus, "t", %{a: 1})
    assert {:ok, 0} = FilteredEventBus.publish(bus, "t", %{a: %{b: nil}})
    assert {:ok, 1} = FilteredEventBus.publish(bus, "t", %{a: %{b: %{c: :x}}})
  end

  test "list indexing via integer keys in path", %{bus: bus} do
    {:ok, _} = FilteredEventBus.subscribe(bus, "t", self(), [{:eq, [:items, 0], :apple}])

    FilteredEventBus.publish(bus, "t", %{items: [:banana, :apple]})
    FilteredEventBus.publish(bus, "t", %{items: [:apple]})
    FilteredEventBus.publish(bus, "t", %{items: []})

    assert [%{items: [:apple]}] = drain("t")
  end

  # -------------------------------------------------------
  # Filter validation
  # -------------------------------------------------------

  test "invalid filters are rejected at subscribe", %{bus: bus} do
    assert {:error, :invalid_filter} =
             FilteredEventBus.subscribe(bus, "t", self(), [{:unknown_op, [:a], 1}])

    assert {:error, :invalid_filter} =
             FilteredEventBus.subscribe(bus, "t", self(), [{:eq, "not_a_list", 1}])

    assert {:error, :invalid_filter} =
             FilteredEventBus.subscribe(bus, "t", self(), [{:any, []}])

    assert {:error, :invalid_filter} =
             FilteredEventBus.subscribe(bus, "t", self(), [{:eq, [3.14], 1}])
  end

  # -------------------------------------------------------
  # test_filter pure helper
  # -------------------------------------------------------

  test "test_filter returns booleans without a running bus" do
    assert true = FilteredEventBus.test_filter([{:eq, [:a], 1}], %{a: 1})
    assert false == FilteredEventBus.test_filter([{:eq, [:a], 1}], %{a: 2})

    assert true = FilteredEventBus.test_filter([], %{anything: true})

    # Same validation as subscribe
    assert {:error, :invalid_filter} =
             FilteredEventBus.test_filter([{:bogus, [:a], 1}], %{a: 1})
  end

  # -------------------------------------------------------
  # Multiple subscriptions per pid — one delivery per matching sub
  # -------------------------------------------------------

  test "one pid with multiple filter subscriptions gets one event per matching sub", %{bus: bus} do
    {:ok, _r1} = FilteredEventBus.subscribe(bus, "t", self(), [{:gt, [:n], 0}])
    {:ok, _r2} = FilteredEventBus.subscribe(bus, "t", self(), [{:lt, [:n], 100}])

    FilteredEventBus.publish(bus, "t", %{n: 50})
    # Matches both filters → two deliveries
    assert [%{n: 50}, %{n: 50}] = drain("t")

    FilteredEventBus.publish(bus, "t", %{n: -5})
    # Matches only the lt filter → one delivery
    assert [%{n: -5}] = drain("t")

    FilteredEventBus.publish(bus, "t", %{n: 500})
    # Matches only the gt filter → one delivery
    assert [%{n: 500}] = drain("t")
  end

  # -------------------------------------------------------
  # matched_count
  # -------------------------------------------------------

  test "publish returns count of subscribers that received the event", %{bus: bus} do
    {:ok, _} = FilteredEventBus.subscribe(bus, "t", self(), [{:gt, [:n], 0}])
    {:ok, _} = FilteredEventBus.subscribe(bus, "t", self(), [{:gt, [:n], 100}])

    assert {:ok, 2} = FilteredEventBus.publish(bus, "t", %{n: 500})
    assert {:ok, 1} = FilteredEventBus.publish(bus, "t", %{n: 50})
    assert {:ok, 0} = FilteredEventBus.publish(bus, "t", %{n: -5})

    _ = drain("t")
  end

  # -------------------------------------------------------
  # DOWN cleanup
  # -------------------------------------------------------

  test "dead subscriber is removed from all topics", %{bus: bus} do
    task =
      Task.async(fn ->
        {:ok, _} = FilteredEventBus.subscribe(bus, "a", self())
        {:ok, _} = FilteredEventBus.subscribe(bus, "b", self(), [{:eq, [:x], 1}])
        :ready
      end)

    assert :ready = Task.await(task)

    # The bus processes the :DOWN message asynchronously, so poll through the
    # documented publish/3 matched-count until both subscriptions are gone.
    # Internal state is deliberately not inspected; the observable contract is
    # that a dead subscriber no longer counts as a match on any of its topics.
    removed? =
      Enum.any?(1..50, fn _ ->
        if FilteredEventBus.publish(bus, "a", %{}) == {:ok, 0} and
             FilteredEventBus.publish(bus, "b", %{x: 1}) == {:ok, 0} do
          true
        else
          Process.sleep(10)
          false
        end
      end)

    assert removed?
    assert Process.alive?(bus)
  end

  # -------------------------------------------------------
  # Unsubscribe
  # -------------------------------------------------------

  test "unsubscribe removes a specific subscription", %{bus: bus} do
    {:ok, r1} = FilteredEventBus.subscribe(bus, "t", self(), [{:gt, [:n], 0}])
    {:ok, _r2} = FilteredEventBus.subscribe(bus, "t", self(), [{:lt, [:n], 0}])

    :ok = FilteredEventBus.unsubscribe(bus, "t", r1)

    FilteredEventBus.publish(bus, "t", %{n: 5})
    assert [] = drain("t")

    FilteredEventBus.publish(bus, "t", %{n: -5})
    assert [%{n: -5}] = drain("t")
  end
end
```
