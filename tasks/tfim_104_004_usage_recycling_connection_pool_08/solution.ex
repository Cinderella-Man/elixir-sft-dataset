  test "a crashed holder's connection is reclaimed and the crash counts as a use" do
    {_counter, create} = counting_create()
    {destroy, destroyed} = destroy_tracker()

    start_supervised!(
      {RecyclingPool, name: :rp_crash, max_size: 1, max_uses: 1, create: create, destroy: destroy}
    )

    {holder, {:ok, c0}} = spawn_holder(:rp_crash, 5_000)
    assert c0 == {:conn, 0}

    Process.exit(holder, :kill)

    # The crash counted as a use (max_uses: 1) → c0 retired; next checkout is fresh.
    assert {:ok, c1} = RecyclingPool.checkout(:rp_crash, 5_000)
    assert c1 != c0
    assert c1 == {:conn, 1}
    assert destroyed.() == [c0]
  end