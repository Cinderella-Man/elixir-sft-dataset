    test "reports :ok when under budget" do
      {:ok, c} = Clock.Fake.start_link([])

      assert {:ok, :work, 50} =
               Timed.run(c, 100, fn ->
                 Clock.Fake.advance(c, milliseconds: 50)
                 :work
               end)
    end