  test "unquoted href values keep their slashes" do
    assert Sanitizer.html("<a href=https://example.com/path>link</a>") ==
             ~s[<a href="https://example.com/path">link</a>]
  end