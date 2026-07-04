  test "errors per hour buckets are correct", %{report: r} do
    # Hour 10: errors at 10:10, 10:15, 10:20 → 3
    # Hour 11: errors at 11:00, 11:45 → 2
    assert r.errors_per_hour == %{
             {{2024, 1, 15}, 10} => 3,
             {{2024, 1, 15}, 11} => 2
           }
  end