  test "push rejects non-numeric" do
    {:ok, c} = CusumAnomaly.start_link()

    assert_raise FunctionClauseError, fn -> CusumAnomaly.push(c, "s", :nope) end
  end