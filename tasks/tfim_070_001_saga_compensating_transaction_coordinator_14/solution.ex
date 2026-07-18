  test "actions of steps after the failing step are never invoked" do
    result =
      Saga.new()
      |> Saga.step(
        :a,
        fn _ctx ->
          track(:actions_run, :a)
          {:ok, 1}
        end,
        fn _ctx -> nil end
      )
      |> Saga.step(
        :b,
        fn _ctx ->
          track(:actions_run, :b)
          {:error, :stop_here}
        end,
        fn _ctx -> nil end
      )
      |> Saga.step(
        :c,
        fn _ctx ->
          track(:actions_run, :c)
          {:ok, 3}
        end,
        fn _ctx -> nil end
      )
      |> Saga.execute(%{})

    assert {:error, :b, :stop_here, _comp} = result
    assert tracked(:actions_run) == [:a, :b]
  end