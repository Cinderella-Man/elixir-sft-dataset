  test "missing key/value/priority return :error", %{bm: bm} do
    assert :error = PriorityBiMap.get_by_key(bm, :nope)
    assert :error = PriorityBiMap.get_by_value(bm, 999)
    assert :error = PriorityBiMap.priority(bm, :nope)
  end