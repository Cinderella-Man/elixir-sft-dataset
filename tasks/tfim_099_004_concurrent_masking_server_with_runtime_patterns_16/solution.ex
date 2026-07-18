  test "keys_masked stays exact under concurrent callers", %{s: s} do
    1..50
    |> Enum.map(fn _ ->
      Task.async(fn -> MaskingServer.mask(s, %{password: "x", note: "hi"}) end)
    end)
    |> Enum.each(&Task.await/1)

    assert MaskingServer.stats(s).keys_masked == 50
  end