  test "uncompensated lists every skipped step in reverse completion order" do
    saga =
      PolicySaga.new()
      |> PolicySaga.step(:a, ok_action(:a, 1), comp(:a))
      |> PolicySaga.step(:b, ok_action(:b, 2), comp(:b))
      |> PolicySaga.step(:c, ok_action(:c, 3), comp(:c, {:error, :undo_failed}), on_error: :abort)
      |> PolicySaga.step(:d, fail_action(:d, :boom), comp(:d))

    assert {:error, err} = PolicySaga.execute(saga, %{})
    assert err.compensated == [:c]
    assert err.aborted_at == :c
    assert err.uncompensated == [:b, :a]
    assert Recorder.comps() == [{:comp, :c}]
  end