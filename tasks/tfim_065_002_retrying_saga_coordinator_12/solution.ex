  test "the reported error is the reason from the final attempt, not the first" do
    saga =
      RetrySaga.new()
      |> RetrySaga.step(:a, flaky_action(:a, 0, 1), comp(:a))
      |> RetrySaga.step(:b, flaky_action(:b, 5, :never), comp(:b), max_attempts: 3)

    assert {:error, err} = RetrySaga.execute(saga, %{})
    assert err.step == :b
    # flaky_action reports {:attempt, n}; the last of 3 attempts is n == 3.
    assert err.error == {:attempt, 3}
    assert err.attempts == 3
    assert Recorder.actions(:b) == 3
  end