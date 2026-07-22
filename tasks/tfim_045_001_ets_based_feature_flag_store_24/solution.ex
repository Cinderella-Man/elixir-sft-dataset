  test "reads deliver no message to the server while writes do", %{pid: pid} do
    FeatureFlags.enable(:traced_on)
    FeatureFlags.enable_for_percentage(:traced_pct, 100)

    :erlang.trace(pid, true, [:receive])

    try do
      # Every read answers correctly from the named table...
      assert FeatureFlags.enabled?(:traced_on)
      assert FeatureFlags.enabled_for?(:traced_pct, "user:1")
      refute FeatureFlags.enabled?(:traced_pct)
      refute FeatureFlags.enabled_for?(:traced_unknown, "user:1")

      # ...without the server process receiving anything at all.
      refute_receive {:trace, ^pid, :receive, _}, 200

      # A write, by contrast, is serialised through the server, which proves
      # the observation above was not silently blind.
      FeatureFlags.enable(:traced_write)
      assert_receive {:trace, ^pid, :receive, _}, 1_000
    after
      :erlang.trace(pid, false, [:receive])
    end
  end