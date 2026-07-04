  test ":abort policy stops the rollback and leaves earlier steps uncompensated" do
    saga =
      PolicySaga.new()
      |> PolicySaga.step(:a, ok_action(:a, 1), comp(:a))
      |> PolicySaga.step(:b, ok_action(:b, 2), comp(:b, {:error, :undo_failed}), on_error: :abort)
      |> PolicySaga.step(:c, ok_action(:c, 3), comp(:c))
      |> PolicySaga.step(:d, fail_action(:d, :fail), comp(:d))

    assert {:error, err} = PolicySaga.execute(saga, %{})

    assert err.step == :d
    # Reverse completion order is c, b, a. c runs (ok), b runs (error → abort).
    assert err.compensated == [:c, :b]
    assert err.compensations == %{c: {:ok, :compensated}, b: {:error, :undo_failed}}
    assert err.aborted_at == :b
    assert err.uncompensated == [:a]

    # a's compensation must NOT have run.
    assert Recorder.comps() == [{:comp, :c}, {:comp, :b}]
  end