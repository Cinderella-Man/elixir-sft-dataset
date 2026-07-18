  test "the longest-waiting blocked caller is served before a later one" do
    start_supervised!({ValidatingPool, name: :vp_fifo, max_size: 1})
    assert {:ok, c} = ValidatingPool.checkout(:vp_fifo, 100)

    parent = self()

    waiter = fn tag ->
      spawn(fn ->
        send(parent, {tag, ValidatingPool.checkout(:vp_fifo, 2_000)})

        # Stay alive: a dead waiter would trigger crash reclamation.
        receive do
          :release -> :ok
        end
      end)
    end

    waiter.(:first)
    refute_receive {:first, _}, 100
    waiter.(:second)
    refute_receive {:second, _}, 100

    assert :ok = ValidatingPool.checkin(:vp_fifo, c)
    assert_receive {:first, {:ok, ^c}}, 1_000
    refute_receive {:second, _}, 100
  end