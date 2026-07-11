  test "stats reflects available / in_use / total" do
    start_supervised!({Pool, name: :pool_stats, min_size: 0, max_size: 3})

    assert %{available: 0, in_use: 0, total: 0, max: 3} = Pool.stats(:pool_stats)

    assert {:ok, c1} = Pool.checkout(:pool_stats, 100)
    s1 = Pool.stats(:pool_stats)
    assert s1.in_use == 1
    assert s1.total == 1
    assert s1.available == 0

    assert {:ok, _c2} = Pool.checkout(:pool_stats, 100)
    s2 = Pool.stats(:pool_stats)
    assert s2.in_use == 2
    assert s2.total == 2

    assert :ok = Pool.checkin(:pool_stats, c1)
    s3 = Pool.stats(:pool_stats)
    assert s3.in_use == 1
    assert s3.available == 1
    assert s3.total == 2
  end