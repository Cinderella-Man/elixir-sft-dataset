  test "abort on the last compensation leaves nothing uncompensated" do
    saga =
      PolicySaga.new()
      |> PolicySaga.step(:a, ok_action(:a, 1), comp(:a, {:error, :undo_failed}), on_error: :abort)
      |> PolicySaga.step(:b, fail_action(:b, :boom), comp(:b))

    assert {:error, err} = PolicySaga.execute(saga, %{})
    assert err.compensated == [:a]
    assert err.compensations == %{a: {:error, :undo_failed}}
    assert err.aborted_at == :a
    assert err.uncompensated == []
  end