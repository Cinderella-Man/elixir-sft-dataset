  test "error map contains exactly the four documented keys and nothing else" do
    saga =
      Saga.new()
      |> Saga.step(:a, ok_action(:a, 1), comp(:a))
      |> Saga.step(:b, fail_action(:b, :nope), comp(:b))

    assert {:error, err} = Saga.execute(saga, %{})

    assert Enum.sort(Map.keys(err)) == [:compensated, :compensations, :error, :step]
  end