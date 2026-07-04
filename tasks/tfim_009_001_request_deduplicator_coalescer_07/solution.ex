  test "key is cleared after successful execution, allowing a fresh call", %{dd: dd} do
    assert {:ok, 1} = Dedup.execute(dd, "k", fn -> {:ok, 1} end)
    # Second call should trigger a new execution, not return stale data
    assert {:ok, 2} = Dedup.execute(dd, "k", fn -> {:ok, 2} end)
  end