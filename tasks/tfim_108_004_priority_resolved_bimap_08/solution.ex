  test "single value-side conflict is displaced when priority wins", %{bm: bm} do
    PriorityBiMap.put(bm, :p, 1, 10)

    # :q wants value 1 (held by :p). 20 > 10 -> accept, displace (p,1).
    assert {:ok, evicted} = PriorityBiMap.put(bm, :q, 1, 20)
    assert evicted == [{:p, 1}]

    assert :error = PriorityBiMap.get_by_key(bm, :p)
    assert {:ok, :q} = PriorityBiMap.get_by_value(bm, 1)
    assert {:ok, 1} = PriorityBiMap.get_by_key(bm, :q)
    assert {:ok, 20} = PriorityBiMap.priority(bm, :q)
  end