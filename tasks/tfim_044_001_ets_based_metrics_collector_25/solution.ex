  test "start_link registers the server under a custom :name option" do
    :ok = stop_supervised(Metrics)

    pid = start_supervised!({Metrics, name: :custom_metrics_server})

    assert Process.whereis(:custom_metrics_server) == pid
    assert :ok = Metrics.increment(:via_custom_name, 2)
    assert Metrics.get(:via_custom_name) == 2
  end