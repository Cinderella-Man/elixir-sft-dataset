    test "strict mode rejects dirty input" do
      assert {:error, [:removed_illegal_chars]} =
               Sanitizer.sql_identifier("us;ers", mode: :strict)
    end