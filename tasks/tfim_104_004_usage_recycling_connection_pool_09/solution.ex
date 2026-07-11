  test "a blocked checkout is served when a connection is returned" do
    start_supervised!({RecyclingPool, name: :rp_serve, max_size: 2, max_uses: 10})
    {:ok, c1} = RecyclingPool.checkout(:rp_serve, 2_000)
    {:ok, _c2} = RecyclingPool.checkout(:rp_serve, 2_000)

    parent = self()
    spawn(fn -> send(parent, {:result, RecyclingPool.checkout(:rp_serve, 5_000)}) end)
    Process.sleep(50)
    refute_received {:result, _}

    assert :ok = RecyclingPool.checkin(:rp_serve, c1)
    assert_receive {:result, {:ok, _conn}}, 5_000
  end