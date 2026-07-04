  test "retriable step exhaustion returns error and compensates nothing" do
    Process.put(:comp, [])

    result =
      Saga.new()
      |> Saga.step(:reserve, fn _ -> {:ok, :r} end, fn _ -> track(:comp, :reserve) end)
      |> Saga.retriable(:commit, fn _ -> {:error, :down} end, 3)
      |> Saga.execute(%{})

    assert {:error, :commit, {:retries_exhausted, :down}, []} = result
    assert tracked(:comp) == []
  end