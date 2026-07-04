  test "key is cleared after error, allowing a fresh call", %{dd: dd} do
    assert {:error, :fail} = Dedup.execute(dd, "k", fn -> {:error, :fail} end)
    # Key is cleared, so this should trigger a new execution
    assert {:ok, :recovered} = Dedup.execute(dd, "k", fn -> {:ok, :recovered} end)
  end