  test ":table_name backs the new server with its own store, not the default table",
       %{pid: default_pid} do
    suffix = "#{System.pid()}_#{System.unique_integer([:positive])}"
    table = String.to_atom("opts_table_#{suffix}")
    server = String.to_atom("opts_server_#{suffix}")

    # Seed a flag through the default server, then bring up a second server
    # configured with its own table and registration name.
    FeatureFlags.enable(:seeded_in_default)
    assert :ets.lookup(:feature_flags, :seeded_in_default) != []

    pid =
      start_supervised!(
        {FeatureFlags, [table_name: table, name: server]},
        id: :opts_feature_flags
      )

    # A distinct process owns a distinct table: the configured table is empty
    # of the default table's flags rather than an alias for it.
    assert pid != default_pid
    assert Process.whereis(server) == pid
    assert :ets.info(table, :owner) == pid
    assert :ets.lookup(table, :seeded_in_default) == []
  end