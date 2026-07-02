  test ":continue policy keeps rolling back past a failed compensation" do
    saga =
      PolicySaga.new()
      |> PolicySaga.step(:a, ok_action(:a, 1), comp(:a, {:ok, :undo_a}))
      |> PolicySaga.step(:b, ok_action(:b, 2), comp(:b, {:error, :undo_failed}), on_error: :continue)
      |> PolicySaga.step(:c, fail_action(:c, :nope), comp(:c))

    assert {:error, err} = PolicySaga.execute(saga, %{})
    assert err.compensated == [:b, :a]
    assert err.compensations == %{b: {:error, :undo_failed}, a: {:ok, :undo_a}}
    assert err.aborted_at == nil
    assert err.uncompensated == []
  end