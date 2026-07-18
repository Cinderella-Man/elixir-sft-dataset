    test "strips path traversal sequences" do
      # Slashes are stripped (not converted to dots), so "etc" and "passwd" are
      # joined directly; strip_dots_ok has no dots to convert → "etcpasswd"
      assert {:ok, "etcpasswd"} = Sanitizer.filename("../etc/passwd") |> strip_dots_ok()
      # The exact result may vary but must not contain .. or /
      {:ok, result} = Sanitizer.filename("../../secret.txt")
      refute result =~ ".."
      refute result =~ "/"
      refute result =~ "\\"
    end