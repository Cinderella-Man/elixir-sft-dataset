  test "a crashing handler leaves the server usable for later batches" do
    boom = fn _batch -> raise "boom" end
    BatchDebouncer.call("crash", 50, :bad, boom)

    BatchDebouncer.call("after", 120, :good, report(:batch))
    assert_receive {:batch, [:good]}, 600

    assert BatchDebouncer.pending("crash") == 0
    assert Process.alive?(Process.whereis(BatchDebouncer))
  end