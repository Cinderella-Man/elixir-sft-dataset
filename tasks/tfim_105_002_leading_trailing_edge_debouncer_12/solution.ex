  test "a raising func does not crash the server" do
    server = Process.whereis(EdgeDebouncer)

    EdgeDebouncer.call("boom_lead", 50, fn -> raise "boom" end, edge: :leading)
    EdgeDebouncer.call("boom_trail", 50, fn -> raise "boom" end)

    # This trailing execution lands after the raising trailing func has fired.
    EdgeDebouncer.call("ok", 100, notify(:settled))
    assert_receive :settled, 600

    # The same process is still registered and still debouncing new bursts.
    assert Process.whereis(EdgeDebouncer) == server

    EdgeDebouncer.call("alive", 50, notify(:alive), edge: :leading)
    assert_receive :alive, 300
  end