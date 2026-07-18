  test "a doubled quote inside a quoted header becomes one literal quote" do
    csv = ~s("a""b",c\n1,2\n)

    assert schema(csv) == %{"a\"b" => :integer, "c" => :integer}
  end