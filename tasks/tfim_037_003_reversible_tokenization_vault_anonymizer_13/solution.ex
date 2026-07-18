    test "a repeated field is applied once, not as a second tokenization pass" do
      records = [%{email: "a@x.com"}, %{email: "b@x.com"}, %{email: "a@x.com"}]
      {once, _v1} = Anonymizer.tokenize(records, [:email])
      {twice, vault} = Anonymizer.tokenize(records, [:email, :email])

      # Listing :email twice yields exactly the single-mention result: no token
      # is fed back in and re-tokenized on the duplicate mention.
      assert twice == once
      assert Enum.map(twice, & &1.email) == ["TOK_EMAIL_1", "TOK_EMAIL_2", "TOK_EMAIL_1"]

      # The round trip stays lossless despite the duplicate field entry.
      assert Anonymizer.detokenize(twice, vault) == records
    end