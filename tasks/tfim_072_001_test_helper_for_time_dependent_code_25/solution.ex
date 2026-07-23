    test "the default applies when only :name is supplied" do
      name =
        String.to_atom("fake_clock_#{System.pid()}_#{System.unique_integer([:positive])}")

      {:ok, _pid} = Clock.Fake.start_link(name: name)
      assert Clock.now(name) == ~U[2024-01-01 00:00:00Z]
    end