  test "omitting :on_error defaults to :continue past a failed compensation" do
    saga =
      PolicySaga.new()
      |> PolicySaga.step(:a, ok_action(:a, 1), comp(:a, {:ok, :undo_a}))
      |> PolicySaga.step(:b, ok_action(:b, 2), comp(:b, {:error, :undo_failed}))
      |> PolicySaga.step(:c, fail_action(:c, :boom), comp(:c))

    assert {:error, err} = PolicySaga.execute(saga, %{})
    assert err.compensated == [:b, :a]
    assert err.compensations == %{b: {:error, :undo_failed}, a: {:ok, :undo_a}}
    assert err.aborted_at == nil
    assert err.uncompensated == []
    assert Recorder.comps() == [{:comp, :b}, {:comp, :a}]
  end