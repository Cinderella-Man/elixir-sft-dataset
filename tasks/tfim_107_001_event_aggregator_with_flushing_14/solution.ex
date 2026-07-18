  test "push returns :ok for both a pid and a registered name" do
    name = :"aggregator_push_ret_#{System.unique_integer([:positive])}"

    pid = start_agg(name: name, batch_size: 5, interval_ms: 5_000)

    assert Aggregator.push(pid, :a) == :ok
    assert Aggregator.push(name, :b) == :ok
  end