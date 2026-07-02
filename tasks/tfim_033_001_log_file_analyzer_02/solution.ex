  test "counts per log level are correct", %{report: r} do
    assert r.counts_by_level == %{
             "info" => 2,
             "debug" => 1,
             "error" => 5,
             "warn" => 1
           }
  end