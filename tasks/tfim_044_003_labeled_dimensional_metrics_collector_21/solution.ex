  test "start_link registers the owning process under a custom :name option" do
    stop_supervised!(Metrics)
    refute Process.whereis(Metrics)

    pid = start_supervised!({Metrics, name: :custom_metrics})
    assert Process.whereis(:custom_metrics) == pid

    Metrics.increment(:requests, %{method: "GET"}, 2)
    assert Metrics.get(:requests, %{method: "GET"}) == 2
  end