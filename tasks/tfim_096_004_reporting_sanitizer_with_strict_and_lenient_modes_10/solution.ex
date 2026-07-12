    test "reports traversal in fixed order" do
      assert {:ok, "etcpasswd", [:removed_path_separators, :collapsed_dots, :trimmed_dots]} =
               Sanitizer.filename("../etc/passwd")
    end