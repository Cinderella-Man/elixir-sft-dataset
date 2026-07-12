    test "cleans a fully valid nested payload" do
      params = %{
        "name" => "  Alice <b>",
        "age" => "42",
        "table" => "users",
        "avatar" => "pic.png",
        "active" => "true",
        "tags" => ["a & b", "<x>"],
        "scores" => [1, "2", 3],
        "profile" => %{"bio" => "hi & bye", "handle" => "1cool"}
      }

      assert {:ok, out} = Sanitizer.sanitize(params, schema())
      assert out["name"] == "Alice &lt;b&gt;"
      assert out["age"] == 42
      assert out["table"] == "users"
      assert out["avatar"] == "pic.png"
      assert out["active"] == true
      assert out["tags"] == ["a &amp; b", "&lt;x&gt;"]
      assert out["scores"] == [1, 2, 3]
      assert out["profile"] == %{"bio" => "hi &amp; bye", "handle" => "_1cool"}
    end