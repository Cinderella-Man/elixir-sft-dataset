  test "values with surrounding whitespace are not trimmed before detection" do
    csv = "n,f\n 1 , 2.5 \n 3 , 4.5 \n"

    assert schema(csv) == %{"n" => :string, "f" => :string}
  end