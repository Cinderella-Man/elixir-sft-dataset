  test "invalid sort field returns error" do
    assert {:error, :invalid_sort_field} =
             KeysetSearch.search(products(), %{"sort" => "inserted_at"})
  end