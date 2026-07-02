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
    {:ok, _} = FilteredEventBus.subscribe(bus, "t", self(), [{:exists, [:session_id]}])

    FilteredEventBus.publish(bus, "t", %{session_id: "abc"})
    FilteredEventBus.publish(bus, "t", %{})
    FilteredEventBus.publish(bus, "t", %{session_id: nil})

    assert [%{session_id: "abc"}] = drain("t")
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

    :sys.get_state(bus)
    state = :sys.get_state(bus)

    for topic <- ["a", "b"] do
      case Map.get(state.topics, topic) do
        nil -> :ok
        subs -> assert subs == []
      end
    end
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
