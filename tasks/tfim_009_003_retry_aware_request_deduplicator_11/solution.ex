  test "key is cleared after success, allowing fresh execution", %{rd: rd} do
    assert {:ok, 1} = RetryDedup.execute(rd, "k", fn -> {:ok, 1} end)
    assert {:ok, 2} = RetryDedup.execute(rd, "k", fn -> {:ok, 2} end)
  end