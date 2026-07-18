  test "every function accepts a raw pid as the server reference", %{pid: pid} do
    assert :ok = BiMap.put(pid, :a, 1)
    assert {:ok, 1} = BiMap.get_by_key(pid, :a)
    assert {:ok, :a} = BiMap.get_by_value(pid, 1)

    assert :ok = BiMap.put(pid, :b, 1)
    assert :error = BiMap.get_by_key(pid, :a)
    assert {:ok, :b} = BiMap.get_by_value(pid, 1)

    assert :ok = BiMap.delete(pid, :b)
    assert :error = BiMap.get_by_key(pid, :b)
    assert :error = BiMap.get_by_value(pid, 1)
  end