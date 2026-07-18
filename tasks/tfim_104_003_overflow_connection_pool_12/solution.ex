  test "a crashed holder's overflow connection is destroyed on reclamation" do
    parent = self()
    destroy = fn conn -> send(parent, {:destroyed, conn}) end

    start_supervised!(
      {OverflowPool, name: :op_crash_ovf, size: 1, max_overflow: 1, destroy: destroy}
    )

    # The base connection stays in use here, so the holder's connection is overflow.
    assert {:ok, _c1} = OverflowPool.checkout(:op_crash_ovf, 100)
    {holder, {:ok, c2}} = spawn_holder(:op_crash_ovf, 1_000)
    assert OverflowPool.stats(:op_crash_ovf).overflow == 1

    Process.exit(holder, :kill)

    # No waiter exists, so the reclaimed overflow connection must be destroyed.
    assert_receive {:destroyed, ^c2}, 1_000

    s = OverflowPool.stats(:op_crash_ovf)
    assert s.total == 1 and s.overflow == 0 and s.in_use == 1 and s.available == 0
  end