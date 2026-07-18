  test "call/4 rejects a max_ms smaller than delay_ms" do
    assert_raise FunctionClauseError, fn ->
      MaxWaitDebouncer.call("k", 200, 100, notify(:never))
    end

    refute_receive :never, 400
  end