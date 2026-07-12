    test "hashes each scalar in a list of scalars (referential integrity within list)" do
      records = [%{tags: ["x", "y", "x"]}]
      [r] = Anonymizer.anonymize(records, %{"tags[]" => :hash})
      assert r.tags == [sha256("x"), sha256("y"), sha256("x")]
    end