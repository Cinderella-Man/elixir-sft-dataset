    test "clean input has no violations" do
      assert {:ok, "report.pdf", []} = Sanitizer.filename("report.pdf")
    end