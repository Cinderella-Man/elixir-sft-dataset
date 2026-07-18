  test "no later action is interleaved between a step's retry attempts" do
    saga =
      RetrySaga.new()
      |> RetrySaga.step(:a, flaky_action(:a, 2, :done), comp(:a), max_attempts: 3)
      |> RetrySaga.step(:b, flaky_action(:b, 1, :ok), comp(:b), max_attempts: 2)

    assert {:ok, _ctx} = RetrySaga.execute(saga, %{})

    assert Recorder.events() == [
             {:action, :a},
             {:action, :a},
             {:action, :a},
             {:action, :b},
             {:action, :b}
           ]
  end