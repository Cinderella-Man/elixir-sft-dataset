  test "a call after a flush starts a brand-new batch" do
    BatchDebouncer.call("k", 100, :one, report(:batch))
    assert_receive {:batch, [:one]}, 400

    BatchDebouncer.call("k", 100, :two, report(:batch))
    assert_receive {:batch, [:two]}, 400
  end