  test "passes through {:error, reason} as-is", %{kp: kp} do
    assert {:error, :boom} = KeyedPool.execute(kp, :k, fn -> {:error, :boom} end)
  end