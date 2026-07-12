  test "range query returns separate results per matched series", %{db: db} do
    :ok = CounterTSDB.insert(db, "reqs", %{"i" => "a"}, 0, 0)
    :ok = CounterTSDB.insert(db, "reqs", %{"i" => "a"}, 500, 10)
    :ok = CounterTSDB.insert(db, "reqs", %{"i" => "b"}, 0, 0)
    :ok = CounterTSDB.insert(db, "reqs", %{"i" => "b"}, 500, 40)

    result = CounterTSDB.query_range(db, "reqs", %{}, {0, 1000}, :increase, 1_000)
    assert length(result) == 2

    incs =
      result
      |> Enum.map(fn {labels, [{0, inc}]} -> {labels["i"], inc} end)
      |> Enum.sort()

    assert incs == [{"a", 10}, {"b", 40}]
  end