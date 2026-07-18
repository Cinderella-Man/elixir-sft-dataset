    test "empty record list returns empty list" do
      assert [] == Anonymizer.anonymize([], %{"a.b" => :hash})
    end