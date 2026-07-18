    test "flags a slow operation deterministically" do
      {:ok, c} = Clock.Fake.start_link([])

      assert {:slow, :work, 300} =
               Timed.run(c, 100, fn ->
                 Clock.Fake.advance(c, milliseconds: 300)
                 :work
               end)
    end