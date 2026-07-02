  test "executes the function and returns the result", %{dd: dd} do
    assert {:ok, 42} = Dedup.execute(dd, "k", fn -> {:ok, 42} end)
  end