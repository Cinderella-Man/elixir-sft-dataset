  test "a doubled quote collapses to one literal quote and stays inside the quoted field" do
    csv = ~s(q\n"a"",b"\n"a,b"\n)

    # row 1 is the value `a",b`, row 2 is `a,b` — distinct, so the column stays unique
    assert schema(csv) == %{"q" => %{type: :string, nullable: false, unique: true}}
  end