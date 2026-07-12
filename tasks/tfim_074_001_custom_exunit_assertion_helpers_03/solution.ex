    test "passes when the function becomes truthy before timeout" do
      counter = :counters.new(1, [])

      assert_eventually(
        fn ->
          :counters.add(counter, 1, 1)
          :counters.get(counter, 1) >= 3
        end,
        500,
        20
      )
    end