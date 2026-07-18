  test "start_link/1 returns {:ok, pid} for a rules map" do
    assert {:ok, pid} = Anonymizer.start_link(%{name: {:pseudonym, "P"}})
    assert is_pid(pid)
    assert Process.alive?(pid)
    assert Anonymizer.mapping(pid, :name) == %{}
  end