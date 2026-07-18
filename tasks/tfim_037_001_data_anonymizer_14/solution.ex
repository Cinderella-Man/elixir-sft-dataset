    test "referential integrity: same value maps to same fake across records in one call" do
      records = [%{id: 1, name: "Bob"}, %{id: 2, name: "Bob"}]
      [r1, r2] = Anonymizer.anonymize(records, %{name: {:fake, "s"}})
      assert r1.name == r2.name
    end