  test "empty saga returns the context unchanged" do
    assert {:ok, %{x: 1}} = Saga.execute(Saga.new(), %{x: 1})
    assert Recorder.events() == []
  end