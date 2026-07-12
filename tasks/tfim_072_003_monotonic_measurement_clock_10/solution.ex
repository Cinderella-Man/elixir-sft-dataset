    test "measures deterministic elapsed time against a fake clock" do
      {:ok, c} = Clock.Fake.start_link([])

      {result, elapsed} =
        Clock.measure(c, fn ->
          Clock.Fake.advance(c, milliseconds: 250)
          :done
        end)

      assert result == :done
      assert elapsed == 250
    end