    test "with a 0ms timeout the function runs exactly once before failing" do
      counter = :counters.new(1, [])

      Enum.each(1..20, fn _ ->
        try do
          assert_eventually(
            fn ->
              :counters.add(counter, 1, 1)
              false
            end,
            0,
            1
          )
        rescue
          ExUnit.AssertionError -> :ok
        end
      end)

      assert :counters.get(counter, 1) == 20
    end