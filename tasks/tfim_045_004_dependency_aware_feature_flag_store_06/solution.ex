  test "enabled_for? requires prerequisites for the same user" do
    FeatureFlags.enable(:child)
    FeatureFlags.set_prerequisites(:child, [:gate])
    FeatureFlags.enable_for_percentage(:gate, 50)

    for i <- 1..300 do
      user = "u#{i}"
      gate_open = :erlang.phash2({:gate, user}, 100) < 50
      assert FeatureFlags.enabled_for?(:child, user) == gate_open
    end
  end