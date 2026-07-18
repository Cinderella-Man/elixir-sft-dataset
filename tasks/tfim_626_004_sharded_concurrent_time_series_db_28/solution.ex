  test "query_agg omits empty windows and returns per-series results", %{db: db} do
    :ok = ShardedTSDB.insert(db, "cpu", %{"host" => "a"}, 100, 10)
    :ok = ShardedTSDB.insert(db, "cpu", %{"host" => "a"}, 200, 20)
    :ok = ShardedTSDB.insert(db, "cpu", %{"host" => "b"}, 100, 100)

    result = ShardedTSDB.query_agg(db, "cpu", %{}, {0, 2000}, :sum, 1_000)
    assert length(result) == 2

    sums =
      result
      |> Enum.map(fn {labels, agg} -> {labels["host"], agg} end)
      |> Enum.sort()

    assert sums == [{"a", [{0, 30}]}, {"b", [{0, 100}]}]
  end