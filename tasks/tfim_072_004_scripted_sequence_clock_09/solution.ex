    test ":raise blows up once the script is exhausted" do
      {:ok, c} = Clock.Fake.start_link(script: [~U[2024-01-01 00:00:00Z]], on_exhaust: :raise)

      assert Clock.Fake.now(c) == ~U[2024-01-01 00:00:00Z]
      assert_raise RuntimeError, fn -> Clock.Fake.now(c) end
    end