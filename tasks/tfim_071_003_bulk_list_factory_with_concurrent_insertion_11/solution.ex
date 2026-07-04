  test "insert_list keeps sequence-driven emails unique under concurrency" do
    users = Factory.insert_list(50, :user)
    emails = Enum.map(users, & &1.email)
    assert length(Enum.uniq(emails)) == 50
  end