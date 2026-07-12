    test "a non-DateTime element fails to start" do
      Process.flag(:trap_exit, true)
      assert {:error, :invalid_script} = Clock.Fake.start_link(script: [:not_a_datetime])
    end