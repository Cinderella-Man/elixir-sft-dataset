  test "filename strips nulls, collapses dot runs and trims edge dots" do
    assert {:ok, "a.b"} = Sanitizer.filename("..a\0...b..")

    assert {:ok, %{"avatar" => "my-pic.png"}} =
             Sanitizer.sanitize(%{"avatar" => "..my-pic..png.."}, %{"avatar" => :filename})
  end