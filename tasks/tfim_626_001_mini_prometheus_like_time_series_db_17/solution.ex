  test "query_agg returns separate aggregations per matched series", %{db: db} do
    :ok = TSDB.insert(db, "cpu", %{"host" => "a"}, 100, 10)
    :ok = TSDB.insert(db, "cpu", %{"host" => "a"}, 200, 20)
    :ok = TSDB.insert(db, "cpu", %{"host" => "b"}, 100, 100)
    :ok = TSDB.insert(db, "cpu", %{"host" => "b"}, 200, 200)

    result = TSDB.query_agg(db, "cpu", %{}, {0, 1000}, :sum, 1_000)

    assert length(result) == 2

    sums =
      result
      |> Enum.map(fn {labels, [{0, sum}]} -> {labels["host"], sum} end)
      |> Enum.sort()

    assert sums == [{"a", 30}, {"b", 300}]
  end