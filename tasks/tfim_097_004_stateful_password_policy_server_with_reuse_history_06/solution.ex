  test "common-password blocklist from startup config is enforced" do
    {:ok, pid} = PasswordPolicy.start_link(common_passwords: ["letmein1!"])

    assert PasswordPolicy.set_password(pid, "operator", "Letmein1!") ==
             {:error, [:common_password]}
  end