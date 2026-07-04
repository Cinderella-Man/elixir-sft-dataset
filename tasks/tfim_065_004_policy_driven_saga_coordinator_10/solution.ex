  test "empty saga returns the context unchanged" do
    assert {:ok, %{x: 1}} = PolicySaga.execute(PolicySaga.new(), %{x: 1})
    assert Recorder.events() == []
  end