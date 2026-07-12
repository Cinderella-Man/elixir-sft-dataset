    test "missing schema keys are skipped, not errored" do
      assert {:ok, out} = Sanitizer.sanitize(%{"name" => "x"}, schema())
      assert out == %{"name" => "x"}
    end