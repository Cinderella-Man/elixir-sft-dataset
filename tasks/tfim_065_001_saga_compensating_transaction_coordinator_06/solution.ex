  test "compensations run in reverse completion order" do
    saga =
      Saga.new()
      |> Saga.step(:a, ok_action(:a, 1), comp(:a))
      |> Saga.step(:b, ok_action(:b, 2), comp(:b))
      |> Saga.step(:c, ok_action(:c, 3), comp(:c))
      |> Saga.step(:d, fail_action(:d, :fail), comp(:d))

    assert {:error, err} = Saga.execute(saga, %{})

    assert err.step == :d
    assert err.compensated == [:c, :b, :a]

    assert Recorder.events() == [
             {:action, :a},
             {:action, :b},
             {:action, :c},
             {:action, :d},
             {:comp, :c},
             {:comp, :b},
             {:comp, :a}
           ]
  end