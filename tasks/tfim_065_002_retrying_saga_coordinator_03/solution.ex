  test "a step that fails twice then succeeds retries and completes" do
    saga =
      RetrySaga.new()
      |> RetrySaga.step(:a, flaky_action(:a, 2, :done), comp(:a), max_attempts: 3)
      |> RetrySaga.step(:b, flaky_action(:b, 0, :ok), comp(:b))

    assert {:ok, ctx} = RetrySaga.execute(saga, %{})
    assert ctx.a == :done
    assert ctx.b == :ok
    assert Recorder.actions(:a) == 3
    # No compensations ran.
    refute Enum.any?(Recorder.events(), &match?({:comp, _}, &1))
  end