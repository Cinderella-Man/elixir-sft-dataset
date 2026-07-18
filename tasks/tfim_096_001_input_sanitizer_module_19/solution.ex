    test "passes through already-safe identifiers unchanged" do
      assert {:ok, "Orders"} = Sanitizer.sql_identifier("Orders")
    end