  test "single successful step" do
    saga = Saga.new() |> Saga.step(:only, ok_action(:only, :done), comp(:only))

    assert {:ok, ctx} = Saga.execute(saga, %{})
    assert ctx.only == :done
    assert Recorder.events() == [{:action, :only}]
  end