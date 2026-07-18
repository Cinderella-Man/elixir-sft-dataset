  test "valid base64 but too-short content returns :malformed" do
    garbage = Base.url_encode64("too short", padding: false)
    assert {:error, :malformed} = open(garbage, @key)
  end