    test "reports illegal chars" do
      assert {:ok, "myfiledraft.docx", [:removed_illegal_chars]} =
               Sanitizer.filename("my file (draft).docx")
    end