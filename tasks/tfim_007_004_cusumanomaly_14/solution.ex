  test "check on unknown stream returns :no_data" do
    {:ok, c} = CusumAnomaly.start_link()
    assert {:error, :no_data} = CusumAnomaly.check(c, "never_seen")
  end