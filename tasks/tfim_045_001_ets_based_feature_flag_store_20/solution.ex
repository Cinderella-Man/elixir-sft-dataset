  test "ETS tables are created with read_concurrency enabled, default and custom" do
    assert :ets.info(:feature_flags, :read_concurrency) == true

    suffix = "#{System.pid()}_#{System.unique_integer([:positive])}"
    table = String.to_atom("rc_table_#{suffix}")
    server = String.to_atom("rc_server_#{suffix}")

    start_supervised!(
      {FeatureFlags, [table_name: table, name: server]},
      id: :read_concurrency_feature_flags
    )

    assert :ets.info(table, :read_concurrency) == true
  end