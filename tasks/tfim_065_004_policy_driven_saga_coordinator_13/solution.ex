  test "actions after the failing step never run" do
    saga =
      PolicySaga.new()
      |> PolicySaga.step(:a, ok_action(:a, 1), comp(:a))
      |> PolicySaga.step(:b, fail_action(:b, :boom), comp(:b))
      |> PolicySaga.step(:c, ok_action(:c, 3), comp(:c))

    assert {:error, err} = PolicySaga.execute(saga, %{})
    assert err.step == :b
    refute {:action, :c} in Recorder.events()
    refute {:comp, :c} in Recorder.events()
    assert Recorder.events() == [{:action, :a}, {:action, :b}, {:comp, :a}]
  end