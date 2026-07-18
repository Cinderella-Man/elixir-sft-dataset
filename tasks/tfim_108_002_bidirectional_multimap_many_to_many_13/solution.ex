  test "any GenServer server reference works, including a bare pid", %{bm: bm, pid: pid} do
    assert :ok = BiMultiMap.put(pid, :a, 1)

    # The pid and the registered name address the very same state.
    assert BiMultiMap.member?(bm, :a, 1)
    assert MapSet.new([1]) == BiMultiMap.get_by_key(pid, :a)
    assert MapSet.new([:a]) == BiMultiMap.get_by_value(pid, 1)

    assert :ok = BiMultiMap.delete(pid, :a, 1)
    refute BiMultiMap.member?(bm, :a, 1)
  end