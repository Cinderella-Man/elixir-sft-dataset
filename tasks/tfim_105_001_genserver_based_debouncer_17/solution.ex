  test "a raising func leaves the server alive and later calls still honored" do
    server = Process.whereis(Debouncer)
    test = self()

    Debouncer.call("boom", 20, fn ->
      send(test, :boom_ran)
      raise "boom"
    end)

    assert_receive :boom_ran, 400

    Debouncer.call("after_boom", 20, notify(:after_ran))
    assert_receive :after_ran, 400

    assert Process.alive?(server)
    assert Process.whereis(Debouncer) == server
  end