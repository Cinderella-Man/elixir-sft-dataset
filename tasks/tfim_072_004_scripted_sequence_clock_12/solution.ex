    test "an unknown policy fails to start" do
      Process.flag(:trap_exit, true)

      assert {:error, :invalid_policy} =
               Clock.Fake.start_link(script: [~U[2024-01-01 00:00:00Z]], on_exhaust: :bogus)
    end