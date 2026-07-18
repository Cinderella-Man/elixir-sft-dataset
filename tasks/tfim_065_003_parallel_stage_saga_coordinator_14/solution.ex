  test "the error map carries exactly the four documented keys" do
    saga =
      ParallelSaga.new()
      |> ParallelSaga.stage([
        {:a, ok_action(:a, 1), comp(:a)},
        {:b, fail_action(:b, :boom), comp(:b)}
      ])

    assert {:error, err} = ParallelSaga.execute(saga, %{})

    assert err |> Map.keys() |> Enum.sort() ==
             [:compensated, :compensations, :failed, :stage]
  end