  test "leading zero-weight variant owns no bucket, not even bucket 0" do
    FeatureFlags.set_variants(:zfirst, [{:z, 0}, {:a, 100}])

    at_0 =
      Enum.find(1..50_000, fn i ->
        :erlang.phash2({:zfirst, "user:#{i}"}, 100) == 0
      end)

    assert is_integer(at_0)
    assert FeatureFlags.variant_for(:zfirst, "user:#{at_0}") == :a

    assignments = for i <- 1..500, do: FeatureFlags.variant_for(:zfirst, "user:#{i}")
    refute Enum.any?(assignments, &(&1 == :z))
  end