  test "arbitrary terms work as keys and values in both directions", %{bm: bm} do
    key = {:tuple, [1, 2], %{nested: "map"}}
    value = %{"list" => [:a, {:b}], other: <<1, 2, 3>>}

    assert {:ok, []} = PriorityBiMap.put(bm, key, value, -5)
    assert {:ok, ^value} = PriorityBiMap.get_by_key(bm, key)
    assert {:ok, ^key} = PriorityBiMap.get_by_value(bm, value)
    assert {:ok, -5} = PriorityBiMap.priority(bm, key)

    assert {:ok, [{^key, ^value}]} = PriorityBiMap.put(bm, "str", value, -4)
    assert :error = PriorityBiMap.get_by_key(bm, key)
    assert {:ok, "str"} = PriorityBiMap.get_by_value(bm, value)
  end