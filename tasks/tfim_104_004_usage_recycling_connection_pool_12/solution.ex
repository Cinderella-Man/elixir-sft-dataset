  test "min_size greater than max_size and a non-positive max_uses are rejected" do
    Process.flag(:trap_exit, true)

    assert {:error, _} = RecyclingPool.start_link(min_size: 3, max_size: 2)
    assert {:error, _} = RecyclingPool.start_link(max_uses: 0)
  end