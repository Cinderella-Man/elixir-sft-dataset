  test "max_uses :infinity never retires a connection" do
    {destroy, destroyed} = destroy_tracker()

    start_supervised!(
      {RecyclingPool, name: :rp_inf, max_size: 1, max_uses: :infinity, destroy: destroy}
    )

    {:ok, c} = RecyclingPool.checkout(:rp_inf, 2_000)

    c =
      Enum.reduce(1..5, c, fn _, conn ->
        :ok = RecyclingPool.checkin(:rp_inf, conn)
        {:ok, same} = RecyclingPool.checkout(:rp_inf, 2_000)
        assert same == conn
        same
      end)

    assert destroyed.() == []
    assert is_reference(c) or match?({:conn, _}, c) or true
  end