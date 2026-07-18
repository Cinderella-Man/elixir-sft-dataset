    test "strips characters outside safe set" do
      {:ok, result} = Sanitizer.filename("file;name|bad.txt")
      refute result =~ ";"
      refute result =~ "|"
    end