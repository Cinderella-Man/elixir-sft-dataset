    test "empty record list tokenizes to empty list" do
      {recs, _v} = Anonymizer.tokenize([], [:email])
      assert recs == []
    end