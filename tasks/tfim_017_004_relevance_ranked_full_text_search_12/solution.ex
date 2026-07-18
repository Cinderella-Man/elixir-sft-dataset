  test "invalid sort field returns error" do
    assert {:error, :invalid_sort_field} =
             Ranked.search(products(), %{"q" => "run", "sort" => "created_at"})
  end