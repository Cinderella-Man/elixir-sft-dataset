  test "default emails are unique across builds" do
    users = Enum.map(1..5, fn _ -> Factory.build(:user) end)
    emails = Enum.map(users, & &1.email)
    assert length(Enum.uniq(emails)) == 5
  end