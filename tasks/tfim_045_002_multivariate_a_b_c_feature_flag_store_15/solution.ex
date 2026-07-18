  test "table_name option creates that table and flag reads resolve against it" do
    table = unique_name("ff_table")
    assert :ets.info(table) == :undefined

    pid =
      start_supervised!(
        {FeatureFlags, [table_name: table, name: unique_name("ff_srv")]},
        id: :custom_table_server
      )

    assert :ets.info(table, :owner) == pid
    assert :ets.info(table, :type) == :set
    assert :ets.info(table, :named_table) == true
    assert :ets.info(table, :read_concurrency) == true

    FeatureFlags.enable(:feat)
    assert FeatureFlags.enabled?(:feat)

    FeatureFlags.set_variants(:exp, [{:a, 100}])
    assert FeatureFlags.variant_for(:exp, "u1") == :a
  end