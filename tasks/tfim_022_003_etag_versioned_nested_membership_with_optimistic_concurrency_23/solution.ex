  test "versions counted from 0 are client-visible: seed yields 1, then POST yields 2", %{
    store: store
  } do
    :ok = TeamStore.create_team(store, "team-fresh")
    :ok = TeamStore.add_member(store, "team-fresh", "alice")

    read = get_members(store, "team-fresh", "token-alice")
    assert read.status == 200
    assert json_body(read)["version"] == 1
    assert etag(read) == "1"

    write = post_member(store, "team-fresh", "bob", "token-alice", "1")
    assert write.status == 201
    assert json_body(write)["version"] == 2
    assert etag(write) == "2"
  end