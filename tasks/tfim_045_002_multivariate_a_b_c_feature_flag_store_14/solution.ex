  test "default options create the named :feature_flags set table owned by the server",
       %{pid: pid} do
    assert :ets.info(:feature_flags, :owner) == pid
    assert :ets.info(:feature_flags, :type) == :set
    assert :ets.info(:feature_flags, :named_table) == true
    assert :ets.info(:feature_flags, :read_concurrency) == true
  end