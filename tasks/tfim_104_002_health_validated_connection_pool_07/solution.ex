  test "a blocked checkout is served when a valid connection is returned" do
    start_supervised!({ValidatingPool, name: :vp_wait, max_size: 2})
    {:ok, c1} = ValidatingPool.checkout(:vp_wait, 100)
    {:ok, _c2} = ValidatingPool.checkout(:vp_wait, 100)

    parent = self()
    spawn(fn -> send(parent, {:result, ValidatingPool.checkout(:vp_wait, 1_000)}) end)
    Process.sleep(50)
    refute_received {:result, _}

    assert :ok = ValidatingPool.checkin(:vp_wait, c1)
    assert_receive {:result, {:ok, _conn}}, 500
  end