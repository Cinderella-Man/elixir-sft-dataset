  test ":abort policy does not fire when that step's compensation succeeds" do
    saga =
      PolicySaga.new()
      |> PolicySaga.step(:a, ok_action(:a, 1), comp(:a))
      |> PolicySaga.step(:b, ok_action(:b, 2), comp(:b, {:ok, :fine}), on_error: :abort)
      |> PolicySaga.step(:c, fail_action(:c, :boom), comp(:c))

    assert {:error, err} = PolicySaga.execute(saga, %{})
    assert err.compensated == [:b, :a]
    assert err.aborted_at == nil
    assert err.uncompensated == []
  end