  test "retries reuse the same context; later steps see earlier results" do
    a = flaky_action(:a, 1, 10)
    b = fn ctx -> {:ok, ctx.a + 5} end

    saga =
      RetrySaga.new()
      |> RetrySaga.step(:a, a, comp(:a), max_attempts: 2)
      |> RetrySaga.step(:b, b, comp(:b))

    assert {:ok, %{a: 10, b: 15}} = RetrySaga.execute(saga, %{})
    assert Recorder.actions(:a) == 2
  end