  test "shard_of returns the documented phash2-based index", %{db: db} do
    expected = :erlang.phash2({"cpu", Enum.sort(Map.to_list(%{"host" => "a"}))}, 4)
    assert ShardedTSDB.shard_of(db, "cpu", %{"host" => "a"}) == expected
    assert ShardedTSDB.shard_of(db, "cpu", %{"host" => "a"}) in 0..3
  end