    test "no tags means zero stripped", %{server: s} do
      assert {:ok, "just text", 0} = Sanitizer.strip_html(s, "just text")
    end