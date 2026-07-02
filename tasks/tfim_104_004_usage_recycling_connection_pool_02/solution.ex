  test "hands out distinct connections up to max_size" do
    start_supervised!({RecyclingPool, name: :rp_distinct, max_size: 2})
    assert {:ok, c1} = RecyclingPool.checkout(:rp_distinct, 100)
    assert {:ok, c2} = RecyclingPool.checkout(:rp_distinct, 100)
    assert c1 != c2
  end