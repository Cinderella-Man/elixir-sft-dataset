  test "actions run strictly in insertion order on the success path" do
    result =
      Saga.new()
      |> Saga.step(
        :third_added,
        fn _ctx ->
          track(:seq, :third_added)
          {:ok, 3}
        end,
        fn _ctx -> nil end
      )
      |> Saga.step(
        :first_added,
        fn _ctx ->
          track(:seq, :first_added)
          {:ok, 1}
        end,
        fn _ctx -> nil end
      )
      |> Saga.step(
        :second_added,
        fn _ctx ->
          track(:seq, :second_added)
          {:ok, 2}
        end,
        fn _ctx -> nil end
      )
      |> Saga.execute(%{})

    assert {:ok, _ctx} = result
    assert tracked(:seq) == [:third_added, :first_added, :second_added]
  end