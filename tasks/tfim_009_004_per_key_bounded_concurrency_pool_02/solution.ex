  test "executes the function and returns the result", %{kp: kp} do
    assert {:ok, 42} = KeyedPool.execute(kp, :k, fn -> {:ok, 42} end)
  end