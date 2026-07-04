  test "assignment matches the cumulative-bucket formula" do
    variants = [{:a, 50}, {:b, 30}, {:c, 20}]
    FeatureFlags.set_variants(:exp, variants)

    for i <- 1..300 do
      user = "user:#{i}"
      bucket = :erlang.phash2({:exp, user}, 100)

      expected =
        cond do
          bucket < 50 -> :a
          bucket < 80 -> :b
          true -> :c
        end

      assert FeatureFlags.variant_for(:exp, user) == expected
    end
  end