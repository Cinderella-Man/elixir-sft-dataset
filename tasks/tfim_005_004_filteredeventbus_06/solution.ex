  test ":gt / :gte / :lt / :lte clauses", %{bus: bus} do
    {:ok, _} = FilteredEventBus.subscribe(bus, "t", self(), [{:gt, [:amount], 1000}])

    for a <- [500, 1000, 1001, 5000], do: FilteredEventBus.publish(bus, "t", %{amount: a})

    assert [%{amount: 1001}, %{amount: 5000}] = drain("t")
  end