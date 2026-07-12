    test "cleans and counts", %{server: s} do
      assert {:ok, "users"} = Sanitizer.sanitize_identifier(s, "us;ers")
      assert {:ok, "_1t"} = Sanitizer.sanitize_identifier(s, "1t")
      assert {:error, :empty} = Sanitizer.sanitize_identifier(s, "!!!")

      m = Sanitizer.metrics(s)
      assert m.identifiers == 3
      assert m.identifiers_blocked == 1
    end