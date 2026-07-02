  test "exhausting retries triggers compensation of earlier steps" do
    saga =
      RetrySaga.new()
      |> RetrySaga.step(:a, flaky_action(:a, 0, 1), comp(:a, {:ok, :undo_a}))
      |> RetrySaga.step(:b, always_fail(:b, :nope), comp(:b), max_attempts: 2)
      |> RetrySaga.step(:c, flaky_action(:c, 0, 3), comp(:c))

    assert {:error, err} = RetrySaga.execute(saga, %{})

    assert err.step == :b
    assert err.error == :nope
    assert err.attempts == 2
    assert err.compensated == [:a]
    assert err.compensations == %{a: {:ok, :undo_a}}

    # b tried twice, c never ran, only a compensated.
    assert Recorder.actions(:a) == 1
    assert Recorder.actions(:b) == 2
    assert Recorder.actions(:c) == 0
    assert Recorder.events() |> Enum.filter(&match?({:comp, _}, &1)) == [{:comp, :a}]
  end