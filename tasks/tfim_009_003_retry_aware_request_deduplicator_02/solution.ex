  test "executes the function and returns the result", %{rd: rd} do
    assert {:ok, 42} = RetryDedup.execute(rd, "k", fn -> {:ok, 42} end)
  end