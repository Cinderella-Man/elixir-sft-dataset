  test "error value carries exactly the documented key set" do
    saga =
      PolicySaga.new()
      |> PolicySaga.step(:a, ok_action(:a, 1), comp(:a))
      |> PolicySaga.step(:b, fail_action(:b, :boom), comp(:b))

    assert {:error, err} = PolicySaga.execute(saga, %{})

    assert err |> Map.keys() |> Enum.sort() ==
             [:aborted_at, :compensated, :compensations, :error, :step, :uncompensated]
  end