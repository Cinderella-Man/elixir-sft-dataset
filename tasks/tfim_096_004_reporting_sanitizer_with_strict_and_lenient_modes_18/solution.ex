    test "strict mode rejects text needing escaping" do
      assert {:error, [:escaped_html]} = Sanitizer.text("a & b", mode: :strict)
    end