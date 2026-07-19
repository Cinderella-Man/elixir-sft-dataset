# Make this test suite pass

Below is a complete, self-contained ExUnit test suite. Treat it as the
full specification: write the module (or modules) under test so that
every test passes. Use only what the tests themselves require — the
standard library and OTP unless the suite references anything else.
Follow idiomatic Elixir house style (`@moduledoc`, `@doc` + `@spec` on
the public API, no compiler warnings).

## The test suite

```elixir
defmodule SanitizerTest do
  use ExUnit.Case, async: false

  defp schema do
    %{
      "name" => :text,
      "age" => :integer,
      "table" => :identifier,
      "avatar" => :filename,
      "active" => :boolean,
      "tags" => {:list, :text},
      "scores" => {:list, :integer},
      "profile" => %{"bio" => :text, "handle" => :identifier}
    }
  end

  describe "Sanitizer.sanitize/2 happy path" do
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

    test "drops keys that are not in the schema (whitelist)" do
      params = %{"name" => "bob", "role" => "admin", "is_admin" => true}
      assert {:ok, out} = Sanitizer.sanitize(params, schema())
      assert out == %{"name" => "bob"}
      refute Map.has_key?(out, "role")
      refute Map.has_key?(out, "is_admin")
    end

    test "missing schema keys are skipped, not errored" do
      assert {:ok, out} = Sanitizer.sanitize(%{"name" => "x"}, schema())
      assert out == %{"name" => "x"}
    end
  end

  describe "Sanitizer.sanitize/2 field cleaning" do
    test "text escapes html special chars and trims" do
      assert {:ok, %{"name" => "&amp;&lt;&gt;&quot;&#39;"}} =
               Sanitizer.sanitize(%{"name" => ~s(  &<>"'  )}, %{"name" => :text})
    end

    test "identifier prepends underscore for digit start" do
      assert {:ok, %{"table" => "_9tbl"}} =
               Sanitizer.sanitize(%{"table" => "9tbl"}, %{"table" => :identifier})
    end

    test "integer coerces clean numeric strings" do
      assert {:ok, %{"age" => 7}} =
               Sanitizer.sanitize(%{"age" => " 7 "}, %{"age" => :integer})
    end

    test "boolean accepts string forms" do
      assert {:ok, %{"active" => false}} =
               Sanitizer.sanitize(%{"active" => "false"}, %{"active" => :boolean})
    end
  end

  describe "Sanitizer.sanitize/2 error reporting" do
    test "reports a bad integer at its path" do
      assert {:error, errors} =
               Sanitizer.sanitize(%{"age" => "not-a-num"}, %{"age" => :integer})

      assert errors[["age"]] == :not_an_integer
    end

    test "reports nested identifier failure with full path" do
      params = %{"profile" => %{"handle" => "!!!"}}
      spec = %{"profile" => %{"handle" => :identifier}}
      assert {:error, errors} = Sanitizer.sanitize(params, spec)
      assert errors[["profile", "handle"]] == :empty
    end

    test "reports list element failure with integer index in path" do
      params = %{"scores" => ["1", "oops", "3"]}
      spec = %{"scores" => {:list, :integer}}
      assert {:error, errors} = Sanitizer.sanitize(params, spec)
      assert errors[["scores", 1]] == :not_an_integer
      refute Map.has_key?(errors, ["scores", 0])
    end

    test "reports type-shape mismatches" do
      assert {:error, %{["profile"] => :expected_map}} =
               Sanitizer.sanitize(%{"profile" => "nope"}, %{"profile" => %{"bio" => :text}})

      assert {:error, %{["tags"] => :expected_list}} =
               Sanitizer.sanitize(%{"tags" => "nope"}, %{"tags" => {:list, :text}})
    end

    test "collects multiple errors across the tree" do
      params = %{"age" => "x", "table" => "###"}
      spec = %{"age" => :integer, "table" => :identifier}
      assert {:error, errors} = Sanitizer.sanitize(params, spec)
      assert map_size(errors) == 2
      assert errors[["age"]] == :not_an_integer
      assert errors[["table"]] == :empty
    end

    test "any error aborts the whole result (no partial ok)" do
      params = %{"name" => "ok", "age" => "bad"}
      assert {:error, _} = Sanitizer.sanitize(params, %{"name" => :text, "age" => :integer})
    end
  end

  describe "public helpers" do
    test "sql_identifier/1" do
      assert {:ok, "users"} = Sanitizer.sql_identifier("us;ers")
      assert {:error, :empty} = Sanitizer.sql_identifier("!!!")
    end

    test "filename/1" do
      assert {:ok, "etcpasswd"} = Sanitizer.filename("../etc/passwd")
      assert {:error, :empty} = Sanitizer.filename("/\\")
    end
  end

  test "text strips C0 controls but keeps tab, newline and carriage return" do
    raw = "  a\x01b\tc\nd\re\x0B\x0C\x1F&  "

    assert {:ok, %{"note" => cleaned}} =
             Sanitizer.sanitize(%{"note" => raw}, %{"note" => :text})

    assert cleaned == "ab\tc\nd\re&amp;"
  end

  test "boolean rejects non-canonical values with not_a_boolean" do
    assert {:error, errors} =
             Sanitizer.sanitize(%{"active" => "TRUE"}, %{"active" => :boolean})

    assert errors[["active"]] == :not_a_boolean

    assert {:error, other} = Sanitizer.sanitize(%{"active" => 1}, %{"active" => :boolean})
    assert other[["active"]] == :not_a_boolean
  end

  test "filename strips nulls, collapses dot runs and trims edge dots" do
    assert {:ok, "a.b"} = Sanitizer.filename("..a\0...b..")

    assert {:ok, %{"avatar" => "my-pic.png"}} =
             Sanitizer.sanitize(%{"avatar" => "..my-pic..png.."}, %{"avatar" => :filename})
  end

  test "text reports not_a_string for non-binary values" do
    assert {:error, errors} = Sanitizer.sanitize(%{"name" => 42}, %{"name" => :text})
    assert errors[["name"]] == :not_a_string

    assert {:error, nested} =
             Sanitizer.sanitize(%{"profile" => %{"bio" => :atom_value}}, %{
               "profile" => %{"bio" => :text}
             })

    assert nested[["profile", "bio"]] == :not_a_string
  end

  test "identifier and filename report not_a_string for non-binary values" do
    assert {:error, errors} =
             Sanitizer.sanitize(%{"table" => 7, "avatar" => ["x"]}, %{
               "table" => :identifier,
               "avatar" => :filename
             })

    assert errors[["table"]] == :not_a_string
    assert errors[["avatar"]] == :not_a_string
  end

  test "list inner spec may itself be a nested schema map" do
    spec = %{"items" => {:list, %{"handle" => :identifier}}}

    assert {:ok, out} =
             Sanitizer.sanitize(%{"items" => [%{"handle" => "1a"}, %{"handle" => "b!"}]}, spec)

    assert out == %{"items" => [%{"handle" => "_1a"}, %{"handle" => "b"}]}

    assert {:error, errors} =
             Sanitizer.sanitize(%{"items" => [%{"handle" => "ok"}, "nope"]}, spec)

    assert errors[["items", 1]] == :expected_map
  end
end
```

Give me the complete implementation in a single file — the module(s)
alone, not the tests.
