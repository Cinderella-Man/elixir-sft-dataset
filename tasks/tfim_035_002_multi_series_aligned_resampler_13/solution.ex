  test "map of all-empty series returns empty list" do
    assert MultiSeriesResampler.resample(%{a: [], b: []}, @interval, agg: :sum) == []
  end