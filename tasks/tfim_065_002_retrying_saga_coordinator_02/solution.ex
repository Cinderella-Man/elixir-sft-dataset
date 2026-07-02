  test "happy path: single attempt each, results merged, no compensation" do
    saga =
      RetrySaga.new()
      |> RetrySaga.step(:a, flaky_action(:a, 0, 1), comp(:a))
      |> RetrySaga.step(:b, flaky_action(:b, 0, 2), comp(:b))

    assert {:ok, %{a: 1, b: 2}} = RetrySaga.execute(saga, %{})
    assert Recorder.events() == [{:action, :a}, {:action, :b}]
    assert Recorder.actions(:a) == 1
    assert Recorder.actions(:b) == 1
  end