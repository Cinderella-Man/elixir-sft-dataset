    test "passes when the message arrives slightly later" do
      parent = self()

      spawn(fn ->
        Process.sleep(20)
        send(parent, :ping)
      end)

      assert_next_message(:ping, 500)
    end