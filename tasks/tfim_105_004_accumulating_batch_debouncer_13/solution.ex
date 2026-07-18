  test "a call issued from inside a handler starts a fresh batch for the same key" do
    test = self()

    handler = fn batch ->
      send(test, {:first, batch})
      BatchDebouncer.call("k", 60, :again, fn b -> send(test, {:second, b}) end)
    end

    BatchDebouncer.call("k", 60, :one, handler)

    assert_receive {:first, [:one]}, 500
    assert_receive {:second, [:again]}, 500
    refute_receive {:first, _}, 200
  end