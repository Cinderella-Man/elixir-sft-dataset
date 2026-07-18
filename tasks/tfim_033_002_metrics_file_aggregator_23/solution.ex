  test "path that cannot be opened as a file returns an error tuple" do
    dir = Path.join(System.tmp_dir!(), "metric_agg_dir_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)

    assert {:error, _reason} = MetricAggregator.summarize(dir)
  end