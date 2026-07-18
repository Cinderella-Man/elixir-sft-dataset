    test "supports string-keyed maps" do
      records = [%{"user" => %{"email" => "a@x.com"}}]
      [r] = Anonymizer.anonymize(records, %{"user.email" => :hash})
      assert r["user"]["email"] == sha256("a@x.com")
    end