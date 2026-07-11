  test "equal priority is a tie and is rejected", %{bm: bm} do
    PriorityBiMap.put(bm, :m, 1, 5)

    # New key :n wants value 1 (held by :m at prio 5). Tie -> rejected.
    assert {:error, :rejected} = PriorityBiMap.put(bm, :n, 1, 5)

    assert {:ok, :m} = PriorityBiMap.get_by_value(bm, 1)
    assert :error = PriorityBiMap.get_by_key(bm, :n)
  end