    test "restores original records exactly" do
      records = [
        %{id: 1, email: "a@x.com", ssn: "111"},
        %{id: 2, email: "a@x.com", ssn: "222"}
      ]

      {tokenized, vault} = Anonymizer.tokenize(records, [:email, :ssn])
      refute tokenized == records
      assert Anonymizer.detokenize(tokenized, vault) == records
    end