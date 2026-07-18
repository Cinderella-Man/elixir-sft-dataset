  test "registers under :name and accepts pushes addressed to that name" do
    name = :"keyed_aggregator_named_#{System.unique_integer([:positive])}"
    start_agg(name: name, batch_size: 2, interval_ms: 30_000)

    assert is_pid(Process.whereis(name))

    assert KeyedAggregator.push(name, :a, 1) == :ok
    assert KeyedAggregator.push(name, :a, 2) == :ok

    assert_receive {:flushed, :a, [1, 2]}, 1_000
  end