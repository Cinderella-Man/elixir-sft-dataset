  test "the most recently started instance serves the module-level API", %{pid: default_pid} do
    suffix = "#{System.pid()}_#{System.unique_integer([:positive])}"
    table = String.to_atom("routed_table_#{suffix}")
    server = String.to_atom("routed_server_#{suffix}")

    second =
      start_supervised!(
        {FeatureFlags, [table_name: table, name: server]},
        id: :routed_flags
      )

    # Writes route to the LAST-started instance: the flag lands in ITS
    # table (presence only — the stored value shape is the module's own
    # business), owned by the second server...
    assert :ok = FeatureFlags.enable(:routed_flag)
    assert [{:routed_flag, _}] = :ets.lookup(table, :routed_flag)
    assert :ets.info(table, :owner) == second

    # ...module-level reads serve it through the published table...
    assert FeatureFlags.enabled?(:routed_flag)

    # ...and the default instance's table never saw the write.
    assert :ets.lookup(:feature_flags, :routed_flag) == []
    assert :ets.info(:feature_flags, :owner) == default_pid
  end