  test "samples_per_hour buckets are correct", %{report: r} do
    # Hour 10: 4 samples (10:00, 10:05, 10:10, 10:20)
    # Hour 11: 2 samples (11:00, 11:30)
    # Hour 12: 1 sample  (12:00)
    assert r.samples_per_hour == %{
             {{2024, 1, 15}, 10} => 4,
             {{2024, 1, 15}, 11} => 2,
             {{2024, 1, 15}, 12} => 1
           }
  end