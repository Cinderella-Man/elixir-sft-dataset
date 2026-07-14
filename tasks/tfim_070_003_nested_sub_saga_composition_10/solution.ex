  test "compensating a fully-succeeded nested step recurses into its own nested steps" do
    Process.put(:order, [])

    inner =
      Saga.new()
      |> Saga.step(:i1, fn _ -> {:ok, :r1} end, fn _ ->
        track(:i1)
        :ui1
      end)
      |> Saga.step(:i2, fn _ -> {:ok, :r2} end, fn _ ->
        track(:i2)
        :ui2
      end)

    middle =
      Saga.new()
      |> Saga.step(:m1, fn _ -> {:ok, :rm} end, fn _ ->
        track(:m1)
        :um1
      end)
      |> Saga.nest(:grand, inner)

    result =
      Saga.new()
      |> Saga.nest(:child, middle)
      |> Saga.step(:last, fn _ -> {:error, :late} end, fn _ -> :ulast end)
      |> Saga.execute(%{})

    assert {:error, [:last], :late, comp} = result
    # every level of the completed tree unwinds, innermost-last-first
    assert comp == [child: [grand: [i2: :ui2, i1: :ui1], m1: :um1]]
    assert order() == [:i2, :i1, :m1]
  end