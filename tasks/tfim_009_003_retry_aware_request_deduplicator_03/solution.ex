  test "wraps plain return values in an ok tuple", %{rd: rd} do
    assert {:ok, "hello"} = RetryDedup.execute(rd, "k", fn -> "hello" end)
  end