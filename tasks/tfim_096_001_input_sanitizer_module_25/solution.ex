    test "returns error for empty result" do
      assert {:error, :empty} = Sanitizer.filename("../../../")
      assert {:error, :empty} = Sanitizer.filename("")
      assert {:error, :empty} = Sanitizer.filename("\0\0\0")
    end