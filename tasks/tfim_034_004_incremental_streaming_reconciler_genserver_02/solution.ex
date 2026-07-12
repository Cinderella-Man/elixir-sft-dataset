  test "start_link returns a live pid and stop/1 shuts it down" do
    {:ok, pid} = StreamReconciler.start_link(key_fields: [:id])
    assert Process.alive?(pid)
    assert StreamReconciler.stop(pid) == :ok
    refute Process.alive?(pid)
  end