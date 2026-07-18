    test "type mismatch along a path is skipped" do
      records = [%{user: "not-a-map"}]
      [r] = Anonymizer.anonymize(records, %{"user.email" => :redact})
      assert r.user == "not-a-map"
    end