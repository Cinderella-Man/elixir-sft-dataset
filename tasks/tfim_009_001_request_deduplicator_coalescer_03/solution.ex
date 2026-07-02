  test "wraps plain return values in an ok tuple", %{dd: dd} do
    assert {:ok, "hello"} = Dedup.execute(dd, "k", fn -> "hello" end)
  end