  test "the error map carries exactly the five documented keys" do
    saga =
      RetrySaga.new()
      |> RetrySaga.step(:a, flaky_action(:a, 0, 1), comp(:a))
      |> RetrySaga.step(:b, always_fail(:b, :nope), comp(:b))

    assert {:error, err} = RetrySaga.execute(saga, %{})

    assert err |> Map.keys() |> Enum.sort() ==
             [:attempts, :compensated, :compensations, :error, :step]
  end