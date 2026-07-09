  test "order preserved even when tasks finish out of order" do
    assert {:ok, results} =
             FailFastMap.pmap(
               1..6,
               fn x ->
                 Process.sleep((7 - x) * 20)
                 x
               end,
               6
             )

    assert results == Enum.to_list(1..6)
  end