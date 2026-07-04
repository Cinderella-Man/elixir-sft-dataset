  test "failure inside a sub-saga compensates inner then outer; path reflects nesting" do
    Process.put(:order, [])

    sub =
      Saga.new()
      |> Saga.step(:x, fn _ -> {:ok, 1} end, fn _ ->
        track(:sub_x)
        :ux
      end)
      |> Saga.step(:y, fn _ -> {:error, :bad} end, fn _ ->
        track(:sub_y)
        :uy
      end)

    result =
      Saga.new()
      |> Saga.step(:a, fn _ -> {:ok, :aa} end, fn _ ->
        track(:a)
        :ua
      end)
      |> Saga.nest(:child, sub)
      |> Saga.step(:c, fn _ -> {:ok, :cc} end, fn _ ->
        track(:c)
        :uc
      end)
      |> Saga.execute(%{})

    assert {:error, [:child, :y], :bad, comp} = result
    assert comp == [child: [x: :ux], a: :ua]
    # :y never completed so it is not compensated; :c never ran
    assert order() == [:sub_x, :a]
  end