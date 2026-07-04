  test "compensations run in reverse completion order" do
    saga =
      RetrySaga.new()
      |> RetrySaga.step(:a, flaky_action(:a, 0, 1), comp(:a))
      |> RetrySaga.step(:b, flaky_action(:b, 0, 2), comp(:b))
      |> RetrySaga.step(:c, flaky_action(:c, 0, 3), comp(:c))
      |> RetrySaga.step(:d, always_fail(:d, :fail), comp(:d))

    assert {:error, err} = RetrySaga.execute(saga, %{})
    assert err.compensated == [:c, :b, :a]

    comps = Enum.filter(Recorder.events(), &match?({:comp, _}, &1))
    assert comps == [{:comp, :c}, {:comp, :b}, {:comp, :a}]
  end