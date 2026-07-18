  test "the backing table is a public named set tuned for concurrent access" do
    assert :ets.info(Metrics, :type) == :set
    assert :ets.info(Metrics, :named_table) == true
    assert :ets.info(Metrics, :protection) == :public
    assert :ets.info(Metrics, :read_concurrency) == true
    assert :ets.info(Metrics, :write_concurrency) == true
  end