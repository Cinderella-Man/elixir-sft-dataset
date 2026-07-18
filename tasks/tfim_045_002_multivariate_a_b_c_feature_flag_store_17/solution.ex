  test "name nil starts the server without registering it" do
    table = unique_name("ff_table")

    pid =
      start_supervised!({FeatureFlags, [table_name: table, name: nil]}, id: :anonymous_server)

    assert Process.info(pid, :registered_name) == {:registered_name, []}
    assert :ets.info(table, :owner) == pid
  end