  test "a returned connection is not charged a second use when its old holder later dies" do
    {_counter, create} = counting_create()
    {destroy, destroyed} = destroy_tracker()

    start_supervised!(
      {RecyclingPool,
       name: :rp_once_use, max_size: 1, max_uses: 2, create: create, destroy: destroy}
    )

    parent = self()

    holder =
      spawn(fn ->
        {:ok, c} = RecyclingPool.checkout(:rp_once_use, 5_000)
        :ok = RecyclingPool.checkin(:rp_once_use, c)
        send(parent, {:returned, c})

        receive do
          :release -> :ok
        end
      end)

    assert_receive {:returned, {:conn, 0}}, 5_000

    ref = Process.monitor(holder)
    Process.exit(holder, :kill)
    assert_receive {:DOWN, ^ref, :process, ^holder, _}, 5_000

    # Only one use was completed, so the connection is still alive and reusable.
    assert {:ok, {:conn, 0}} = RecyclingPool.checkout(:rp_once_use, 2_000)
    assert destroyed.() == []
  end