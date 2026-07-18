  test "start_link honours :table_name and :name options" do
    suffix = "#{System.pid()}_#{System.unique_integer([:positive])}"
    table = String.to_atom("flags_table_#{suffix}")
    server = String.to_atom("flags_server_#{suffix}")

    pid =
      start_supervised!(
        {FeatureFlags, [table_name: table, name: server]},
        id: :custom_feature_flags
      )

    # The process is registered under the requested name...
    assert Process.whereis(server) == pid

    # ...and the ETS table carries the requested name, not the default.
    assert :ets.info(table, :name) == table
    assert :ets.info(table, :named_table) == true
    assert :ets.info(table, :type) == :set
    assert :ets.info(table, :owner) == pid
  end