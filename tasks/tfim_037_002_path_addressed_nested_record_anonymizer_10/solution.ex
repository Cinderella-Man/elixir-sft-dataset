    test "same value at different paths and records yields identical output" do
      records = [
        %{user: %{email: "shared@x.com"}, backup: %{email: "shared@x.com"}},
        %{user: %{email: "shared@x.com"}, backup: %{email: "other@x.com"}}
      ]

      [r1, r2] = Anonymizer.anonymize(records, %{"user.email" => :hash, "backup.email" => :hash})
      assert r1.user.email == r1.backup.email
      assert r1.user.email == r2.user.email
      refute r2.user.email == r2.backup.email
    end