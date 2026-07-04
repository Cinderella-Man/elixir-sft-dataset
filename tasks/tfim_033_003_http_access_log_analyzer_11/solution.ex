  test "requests_per_minute buckets are correct", %{report: r} do
    assert r.requests_per_minute == %{
             {{2024, 1, 15}, {10, 0}} => 2,
             {{2024, 1, 15}, {10, 1}} => 2,
             {{2024, 1, 15}, {10, 2}} => 1,
             {{2024, 1, 15}, {11, 0}} => 1,
             {{2024, 1, 15}, {11, 5}} => 1,
             {{2024, 1, 15}, {12, 0}} => 1
           }
  end