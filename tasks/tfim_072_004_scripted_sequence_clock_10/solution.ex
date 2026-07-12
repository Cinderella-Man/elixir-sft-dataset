    test "an empty script fails to start" do
      Process.flag(:trap_exit, true)
      assert {:error, :empty_script} = Clock.Fake.start_link(script: [])
    end