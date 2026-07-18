  test "phash2 bucketing is consistent with expected formula" do
    FeatureFlags.enable_for_percentage(:p, 10)

    for i <- 1..200 do
      result = FeatureFlags.enabled_for?(:p, "user:#{i}")
      expected = :erlang.phash2({:p, "user:#{i}"}, 100) < 10

      assert result == expected,
             "user:#{i} — got #{result}, expected #{expected}"
    end
  end