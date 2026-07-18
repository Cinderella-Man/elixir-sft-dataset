  test "a checkin serves the next waiter when the longest-waiting one died" do
    start_supervised!({OverflowPool, name: :op_dead_waiter, size: 1, max_overflow: 0})
    parent = self()

    assert {:ok, c1} = OverflowPool.checkout(:op_dead_waiter, 100)

    spawn_waiter = fn tag ->
      spawn(fn ->
        send(parent, {:got, tag, OverflowPool.checkout(:op_dead_waiter, 5_000)})

        receive do
          :release -> :ok
        end
      end)
    end

    first = spawn_waiter.(:first)
    refute_receive {:got, :first, _}, 100
    second = spawn_waiter.(:second)
    refute_receive {:got, :second, _}, 100

    ref = Process.monitor(first)
    Process.exit(first, :kill)
    assert_receive {:DOWN, ^ref, :process, ^first, :killed}, 1_000

    # The only live blocked caller must receive the connection.
    assert :ok = OverflowPool.checkin(:op_dead_waiter, c1)
    assert_receive {:got, :second, {:ok, got}}, 1_000
    assert got == c1

    send(second, :release)
  end