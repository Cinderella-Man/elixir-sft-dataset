  test "build_list elements have unique sequence-driven emails" do
    users = Factory.build_list(6, :user)
    emails = Enum.map(users, & &1.email)
    assert length(Enum.uniq(emails)) == 6
  end