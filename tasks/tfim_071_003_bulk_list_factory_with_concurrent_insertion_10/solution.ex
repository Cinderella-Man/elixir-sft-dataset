  test "insert_list assigns unique ids under concurrency" do
    users = Factory.insert_list(50, :user)
    ids = Enum.map(users, & &1.id)
    assert length(Enum.uniq(ids)) == 50
  end