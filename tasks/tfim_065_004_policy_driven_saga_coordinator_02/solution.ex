  test "happy path: all steps succeed, no compensation" do
    saga =
      PolicySaga.new()
      |> PolicySaga.step(:a, ok_action(:a, 1), comp(:a))
      |> PolicySaga.step(:b, ok_action(:b, 2), comp(:b))

    assert {:ok, %{a: 1, b: 2}} = PolicySaga.execute(saga, %{})
    assert Recorder.comps() == []
  end