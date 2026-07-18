  test "status returns zeros for unknown key", %{kp: kp} do
    assert KeyedPool.status(kp, :nothing) == %{running: 0, queued: 0}
  end