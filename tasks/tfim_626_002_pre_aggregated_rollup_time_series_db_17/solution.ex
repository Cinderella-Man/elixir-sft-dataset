  test "stats map exposes exactly the documented keys and nothing else", %{db: db} do
    :ok = RollupTSDB.insert(db, "m", %{"host" => "a"}, 100, 5)
    :ok = RollupTSDB.insert(db, "m", %{"host" => "a"}, 200, 15)

    [{_labels, [{0, stats}]}] = RollupTSDB.query(db, "m", %{}, {0, 900})

    assert Enum.sort(Map.keys(stats)) == [:avg, :count, :first, :last, :max, :min, :sum]
    assert is_float(stats.avg)
  end