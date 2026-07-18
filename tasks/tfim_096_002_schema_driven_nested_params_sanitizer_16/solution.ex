    test "filename/1" do
      assert {:ok, "etcpasswd"} = Sanitizer.filename("../etc/passwd")
      assert {:error, :empty} = Sanitizer.filename("/\\")
    end