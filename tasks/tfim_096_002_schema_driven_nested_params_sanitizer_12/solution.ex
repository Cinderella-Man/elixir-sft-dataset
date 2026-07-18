    test "reports type-shape mismatches" do
      assert {:error, %{["profile"] => :expected_map}} =
               Sanitizer.sanitize(%{"profile" => "nope"}, %{"profile" => %{"bio" => :text}})

      assert {:error, %{["tags"] => :expected_list}} =
               Sanitizer.sanitize(%{"tags" => "nope"}, %{"tags" => {:list, :text}})
    end