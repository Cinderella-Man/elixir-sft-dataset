  test "allow/2 fails when the owner has no connection" do
    other = spawn(fn -> Process.sleep(50) end)
    assert {:error, :no_owner} = DBCleaner.allow(self(), other)
  end