  test "key is cleaned up when all work finishes", %{kp: kp} do
    KeyedPool.execute(kp, :temp, fn -> {:ok, :done} end)

    # After completion, status should be zero
    assert KeyedPool.status(kp, :temp) == %{running: 0, queued: 0}
  end