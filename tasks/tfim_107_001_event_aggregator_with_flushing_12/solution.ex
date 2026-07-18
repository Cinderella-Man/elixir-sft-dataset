  test "registers under :name and accepts pushes addressed to that name" do
    name = :"aggregator_#{System.pid()}_#{System.unique_integer([:positive])}"

    pid = start_agg(name: name, batch_size: 2, interval_ms: 5_000)

    assert Process.whereis(name) == pid

    # push/2 must accept the registered name, not just a pid.
    Aggregator.push(name, :a)
    Aggregator.push(name, :b)

    assert_receive {:flushed, [:a, :b]}, 500
  end