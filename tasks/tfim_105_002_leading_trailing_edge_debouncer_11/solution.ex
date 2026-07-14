  test "a leading func that never returns does not wedge the server" do
    test = self()

    # Blocks forever until explicitly released, without sleeping the test.
    blocking = fn ->
      send(test, {:blocking_started, self()})

      receive do
        :release -> :ok
      end
    end

    EdgeDebouncer.call("blocked", 100, blocking, edge: :leading)
    assert_receive {:blocking_started, blocker}, 500

    # While that func is still running, the server keeps handling other keys:
    # a leading call fires immediately and a trailing call still settles.
    EdgeDebouncer.call("other", 100, notify(:other_leading), edge: :leading)
    assert_receive :other_leading, 500

    EdgeDebouncer.call("later", 80, notify(:other_trailing))
    assert_receive :other_trailing, 600

    send(blocker, :release)
  end