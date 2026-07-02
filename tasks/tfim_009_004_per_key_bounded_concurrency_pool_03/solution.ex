  test "wraps plain return values in an ok tuple", %{kp: kp} do
    assert {:ok, "hello"} = KeyedPool.execute(kp, :k, fn -> "hello" end)
  end