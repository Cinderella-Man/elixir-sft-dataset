  test "TeamStore registers under the :name option and serves calls by that name" do
    name = :"named_store_#{System.unique_integer([:positive])}"
    start_supervised!(%{id: name, start: {TeamStore, :start_link, [[name: name]]}})

    assert is_pid(Process.whereis(name))
    assert :ok = TeamStore.create_team(name, "team-x")
    assert :ok = TeamStore.create_user(name, "dave", "token-dave")
    assert :ok = TeamStore.add_member(name, "team-x", "dave")
    assert TeamStore.team_exists?(name, "team-x")
    assert TeamStore.is_member?(name, "team-x", "dave")
    assert {:ok, "dave"} = TeamStore.get_user_by_token(name, "token-dave")
    assert {:ok, ["dave"]} = TeamStore.list_members(name, "team-x")
  end