  test "resume continues from a journal without re-running completed actions" do
    Process.put(:ran, [])
    mark = fn n -> Process.put(:ran, [n | Process.get(:ran)]) end

    saga =
      Saga.new()
      |> Saga.step(:a, fn _ ->
        mark.(:a)
        {:ok, 1}
      end, fn _ -> :ua end)
      |> Saga.step(:b, fn _ ->
        mark.(:b)
        {:ok, 2}
      end, fn _ -> :ub end)
      |> Saga.step(:c, fn ctx ->
        mark.(:c)
        {:ok, ctx.a + ctx.b}
      end, fn _ -> :uc end)

    journal = [{:completed, :a, 1}, {:completed, :b, 2}]
    result = Saga.resume(saga, %{}, journal)

    assert {:ok, ctx, jr} = result
    assert ctx.a == 1 and ctx.b == 2 and ctx.c == 3
    # Only :c actually executed during the resume.
    assert Enum.reverse(Process.get(:ran)) == [:c]

    assert jr == [
             {:completed, :a, 1},
             {:completed, :b, 2},
             {:completed, :c, 3}
           ]
  end