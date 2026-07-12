    test "listed fields absent from a record are skipped" do
      records = [%{name: "Al"}]
      {[r], _v} = Anonymizer.tokenize(records, [:email])
      refute Map.has_key?(r, :email)
      assert r.name == "Al"
    end