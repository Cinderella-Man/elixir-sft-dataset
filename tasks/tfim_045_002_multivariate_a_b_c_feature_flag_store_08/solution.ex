  test "distribution roughly matches weights" do
    FeatureFlags.set_variants(:exp, [{:a, 70}, {:b, 30}])
    assignments = for i <- 1..2000, do: FeatureFlags.variant_for(:exp, "user:#{i}")
    a = Enum.count(assignments, &(&1 == :a))
    b = Enum.count(assignments, &(&1 == :b))

    assert a + b == 2000
    assert a >= 1300 and a <= 1500
    assert b >= 500 and b <= 700
  end