  test "quoted header fields keep embedded commas and unescape doubled quotes" do
    csv = ~s|"first,last","say ""hi"""\n1,2\n|

    assert schema(csv) == %{"first,last" => :integer, "say \"hi\"" => :integer}
  end