  test "replacing a retired connection for a waiter keeps total at max_size" do
    {_counter, create} = counting_create()

    start_supervised!(
      {RecyclingPool, name: :rp_repl_total, max_size: 1, max_uses: 1, create: create}
    )

    assert {:ok, c0} = RecyclingPool.checkout(:rp_repl_total, 2_000)
    parent = self()

    holder =
      spawn(fn ->
        send(parent, {:result, RecyclingPool.checkout(:rp_repl_total, 5_000)})

        receive do
          :release -> :ok
        end
      end)

    Process.sleep(50)
    assert :ok = RecyclingPool.checkin(:rp_repl_total, c0)
    assert_receive {:result, {:ok, cnew}}, 5_000
    assert cnew != c0

    s = RecyclingPool.stats(:rp_repl_total)
    assert s.total == 1
    assert s.in_use == 1
    assert s.available == 0

    send(holder, :release)
  end