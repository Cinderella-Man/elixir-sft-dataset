  test "reset on unknown stream returns :ok without creating it" do
    {:ok, c} = CusumAnomaly.start_link()
    assert :ok = CusumAnomaly.reset(c, "ghost")

    # check/2 should still report :no_data
    assert {:error, :no_data} = CusumAnomaly.check(c, "ghost")
  end