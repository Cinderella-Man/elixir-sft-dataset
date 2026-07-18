  test "start_link defaults process registration to the Metrics module name" do
    assert is_pid(Process.whereis(Metrics))

    Metrics.increment(:requests, %{method: "GET"})
    assert Metrics.get(:requests, %{method: "GET"}) == 1
  end