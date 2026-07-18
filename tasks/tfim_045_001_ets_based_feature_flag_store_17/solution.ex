  test "default table is a named :set called :feature_flags owned by the server", %{pid: pid} do
    assert :ets.info(:feature_flags, :name) == :feature_flags
    assert :ets.info(:feature_flags, :named_table) == true
    assert :ets.info(:feature_flags, :type) == :set
    assert :ets.info(:feature_flags, :owner) == pid
  end