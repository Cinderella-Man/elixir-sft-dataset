  test "empty saga returns the context unchanged" do
    assert {:ok, %{x: 1}} = ParallelSaga.execute(ParallelSaga.new(), %{x: 1})
    assert Recorder.events() == []
  end