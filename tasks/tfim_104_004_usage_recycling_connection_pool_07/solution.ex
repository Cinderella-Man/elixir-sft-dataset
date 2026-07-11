  test "a retired connection is replaced with a fresh one for a waiting caller" do
    {_counter, create} = counting_create()
    {destroy, destroyed} = destroy_tracker()

    start_supervised!(
      {RecyclingPool, name: :rp_wait, max_size: 1, max_uses: 1, create: create, destroy: destroy}
    )

    assert {:ok, c0} = RecyclingPool.checkout(:rp_wait, 2_000)
    assert c0 == {:conn, 0}

    parent = self()
    spawn(fn -> send(parent, {:result, RecyclingPool.checkout(:rp_wait, 5_000)}) end)
    Process.sleep(50)
    refute_received {:result, _}

    # Returning c0 completes its only allowed use → retired; the waiter gets a fresh one.
    assert :ok = RecyclingPool.checkin(:rp_wait, c0)
    assert_receive {:result, {:ok, cnew}}, 5_000
    assert cnew != c0
    assert cnew == {:conn, 1}
    assert destroyed.() == [c0]
  end