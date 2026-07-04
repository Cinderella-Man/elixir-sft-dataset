  test "exception is returned as {:error, {:exception, _}}", %{kp: kp} do
    result = KeyedPool.execute(kp, :k, fn -> raise "kaboom" end)
    assert {:error, {:exception, %RuntimeError{message: "kaboom"}}} = result
  end