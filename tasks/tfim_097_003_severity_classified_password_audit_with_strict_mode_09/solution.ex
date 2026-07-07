  test "a fully valid password produces an empty ok report" do
    report =
      PasswordPolicy.audit("Tr0ub4dor&3", %{
        username: "alice",
        common_passwords: ["password123"],
        previous_passwords: ["OldPass1!"]
      })

    assert report == %{status: :ok, errors: [], warnings: []}
  end