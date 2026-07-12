    test "redacts and masks at different nested paths" do
      records = [%{profile: %{ssn: "123-45-6789", first: "Jonathan"}}]
      [r] = Anonymizer.anonymize(records, %{"profile.ssn" => :redact, "profile.first" => :mask})
      assert r.profile.ssn == "[REDACTED]"
      assert r.profile.first == "J******n"
    end