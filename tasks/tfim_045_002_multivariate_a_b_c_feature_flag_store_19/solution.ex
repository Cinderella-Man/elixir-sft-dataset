  test "bucket exactly equal to the first cumulative bound belongs to the next variant" do
    FeatureFlags.set_variants(:bound, [{:a, 50}, {:b, 50}])

    at_50 =
      Enum.find(1..50_000, fn i ->
        :erlang.phash2({:bound, "user:#{i}"}, 100) == 50
      end)

    at_49 =
      Enum.find(1..50_000, fn i ->
        :erlang.phash2({:bound, "user:#{i}"}, 100) == 49
      end)

    assert is_integer(at_50)
    assert is_integer(at_49)
    assert FeatureFlags.variant_for(:bound, "user:#{at_50}") == :b
    assert FeatureFlags.variant_for(:bound, "user:#{at_49}") == :a
  end