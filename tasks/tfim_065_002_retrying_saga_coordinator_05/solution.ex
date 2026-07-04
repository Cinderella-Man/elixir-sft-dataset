  test "default max_attempts is 1 (a single attempt, then failure)" do
    saga =
      RetrySaga.new()
      |> RetrySaga.step(:a, always_fail(:a, :boom), comp(:a))

    assert {:error, err} = RetrySaga.execute(saga, %{})
    assert err.step == :a
    assert err.attempts == 1
    assert err.compensated == []
    assert err.compensations == %{}
    assert Recorder.actions(:a) == 1
  end