  test "name option registers the server process under that name" do
    name = unique_name("ff_named")
    table = unique_name("ff_table")

    pid =
      start_supervised!({FeatureFlags, [table_name: table, name: name]}, id: :named_server)

    assert Process.whereis(name) == pid
  end