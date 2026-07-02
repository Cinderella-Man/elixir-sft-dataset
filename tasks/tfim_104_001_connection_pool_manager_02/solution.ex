  test "hands out distinct connections up to max_size" do
    start_supervised!({Pool, name: :pool_distinct, max_size: 2})

    assert {:ok, c1} = Pool.checkout(:pool_distinct, 100)
    assert {:ok, c2} = Pool.checkout(:pool_distinct, 100)
    assert c1 != c2
  end