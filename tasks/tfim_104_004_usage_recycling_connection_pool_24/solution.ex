  test "a max_uses that is not a positive integer or :infinity is rejected at startup" do
    Process.flag(:trap_exit, true)

    assert {:error, _} = RecyclingPool.start_link(max_uses: :never)
    assert {:error, _} = RecyclingPool.start_link(max_uses: -1)
    assert {:error, _} = RecyclingPool.start_link(max_uses: 1.0)
  end