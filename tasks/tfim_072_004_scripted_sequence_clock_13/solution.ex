    test "defaults to a single-value script when none given" do
      {:ok, c} = Clock.Fake.start_link([])
      assert %DateTime{} = Clock.Fake.now(c)
    end