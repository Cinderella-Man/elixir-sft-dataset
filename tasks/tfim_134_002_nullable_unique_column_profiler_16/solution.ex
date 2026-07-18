  test "a quoted value duplicates an unquoted one with the same characters" do
    csv = ~s(code\n1\n"1"\n)

    assert schema(csv) == %{"code" => %{type: :string, nullable: false, unique: false}}
  end