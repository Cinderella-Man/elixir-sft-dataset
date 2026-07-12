  test "query fans out and merges across many series", %{db: db} do
    for h <- ["a", "b", "c", "d", "e", "f"] do
      :ok = ShardedTSDB.insert(db, "cpu", %{"host" => h}, 100, 1)
    end

    result = ShardedTSDB.query(db, "cpu", %{}, {0, 200})
    hosts = result |> Enum.map(fn {labels, _} -> labels["host"] end) |> Enum.sort()
    assert hosts == ["a", "b", "c", "d", "e", "f"]
  end