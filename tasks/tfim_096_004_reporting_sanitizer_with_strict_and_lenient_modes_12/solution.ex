    test "strict mode rejects dirty filenames" do
      assert {:error, [:removed_path_separators, :collapsed_dots, :trimmed_dots]} =
               Sanitizer.filename("../etc/passwd", mode: :strict)
    end