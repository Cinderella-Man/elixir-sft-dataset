    test "empty result is a hard error" do
      assert {:error, [:empty]} = Sanitizer.filename("/\\")
      assert {:error, [:empty]} = Sanitizer.filename("", mode: :strict)
    end