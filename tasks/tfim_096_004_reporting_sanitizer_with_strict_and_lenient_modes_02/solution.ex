    test "clean input has no violations in either mode" do
      assert {:ok, "users", []} = Sanitizer.sql_identifier("users")
      assert {:ok, "users", []} = Sanitizer.sql_identifier("users", mode: :strict)
    end