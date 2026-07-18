  test "the owned table is public and named" do
    owner = Process.whereis(Metrics)

    owned =
      Enum.filter(:ets.all(), fn table ->
        :ets.info(table, :owner) == owner
      end)

    assert Enum.any?(owned, fn table ->
             :ets.info(table, :protection) == :public and
               :ets.info(table, :named_table) == true
           end)
  end