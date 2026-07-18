  test "report contains exactly the documented keys and stats keys", %{report: r} do
    assert Enum.sort(Map.keys(r)) == [
             :malformed_count,
             :per_metric,
             :samples_per_hour,
             :time_range,
             :total_samples,
             :unique_tags
           ]

    assert Enum.sort(Map.keys(r.per_metric["cpu_usage"])) == [:count, :max, :mean, :min, :sum]
    assert is_float(r.per_metric["mem_usage"].mean)
  end