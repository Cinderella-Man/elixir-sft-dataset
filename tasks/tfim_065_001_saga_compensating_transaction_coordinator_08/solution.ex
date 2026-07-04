  test "a failing compensation is recorded but remaining compensations still run" do
    saga =
      Saga.new()
      |> Saga.step(:a, ok_action(:a, 1), comp(:a, {:ok, :undo_a}))
      |> Saga.step(:b, ok_action(:b, 2), comp(:b, {:error, :undo_failed}))
      |> Saga.step(:c, fail_action(:c, :nope), comp(:c))

    assert {:error, err} = Saga.execute(saga, %{})

    assert err.step == :c
    assert err.error == :nope
    assert err.compensated == [:b, :a]
    assert err.compensations == %{b: {:error, :undo_failed}, a: {:ok, :undo_a}}

    # Even though :b's compensation errored, :a's still ran.
    assert Recorder.events() == [
             {:action, :a},
             {:action, :b},
             {:action, :c},
             {:comp, :b},
             {:comp, :a}
           ]
  end