# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule Sanitizer do
  @moduledoc """
  Schema-driven sanitizer for nested parameter maps.

  `sanitize/2` walks a nested `params` map (string keys) against a declarative
  `schema`, applying per-field cleaning, dropping keys not present in the
  schema (whitelist / mass-assignment protection), and collecting all field
  errors keyed by their path.

  All logic is pure — standard library only, no external dependencies.
  """

  @type field :: atom() | {:list, field()} | map()

  @doc """
  Sanitize `params` against `schema`.

  Returns `{:ok, cleaned}` when every field is valid, otherwise
  `{:error, errors}` where `errors` maps a path (list of string keys and
  integer list indices) to a reason atom.
  """
  @spec sanitize(map(), map()) :: {:ok, map()} | {:error, map()}
  def sanitize(params, schema) when is_map(params) and is_map(schema) do
    {clean, errors} = walk_map(params, schema, [])

    if errors == %{} do
      {:ok, clean}
    else
      {:error, errors}
    end
  end

  # ── Recursion over a map/schema ────────────────────────────────────────────

  defp walk_map(params, schema, path) do
    Enum.reduce(schema, {%{}, %{}}, fn {key, spec}, {acc, errs} ->
      case Map.fetch(params, key) do
        :error ->
          {acc, errs}

        {:ok, value} ->
          case apply_spec(value, spec, path ++ [key]) do
            {:ok, cleaned} -> {Map.put(acc, key, cleaned), errs}
            {:error, field_errs} -> {acc, Map.merge(errs, field_errs)}
          end
      end
    end)
  end

  # ── Field spec dispatch ────────────────────────────────────────────────────

  defp apply_spec(value, {:list, inner}, path) do
    if is_list(value) do
      {clean, errs, _} =
        Enum.reduce(value, {[], %{}, 0}, fn item, {acc, e, i} ->
          case apply_spec(item, inner, path ++ [i]) do
            {:ok, c} -> {[c | acc], e, i + 1}
            {:error, fe} -> {acc, Map.merge(e, fe), i + 1}
          end
        end)

      if errs == %{}, do: {:ok, Enum.reverse(clean)}, else: {:error, errs}
    else
      {:error, %{path => :expected_list}}
    end
  end

  defp apply_spec(value, spec, path) when is_map(spec) do
    if is_map(value) do
      {clean, errs} = walk_map(value, spec, path)
      if errs == %{}, do: {:ok, clean}, else: {:error, errs}
    else
      {:error, %{path => :expected_map}}
    end
  end

  defp apply_spec(value, type, path) when is_atom(type) do
    case sanitize_field(type, value) do
      {:ok, v} -> {:ok, v}
      {:error, reason} -> {:error, %{path => reason}}
    end
  end

  # ── Leaf field sanitizers ──────────────────────────────────────────────────

  defp sanitize_field(:text, v) when is_binary(v), do: {:ok, escape_text(v)}
  defp sanitize_field(:text, _), do: {:error, :not_a_string}

  defp sanitize_field(:identifier, v) when is_binary(v), do: sql_identifier(v)
  defp sanitize_field(:identifier, _), do: {:error, :not_a_string}

  defp sanitize_field(:filename, v) when is_binary(v), do: filename(v)
  defp sanitize_field(:filename, _), do: {:error, :not_a_string}

  defp sanitize_field(:integer, v) when is_integer(v), do: {:ok, v}

  defp sanitize_field(:integer, v) when is_binary(v) do
    case Integer.parse(String.trim(v)) do
      {n, ""} -> {:ok, n}
      _ -> {:error, :not_an_integer}
    end
  end

  defp sanitize_field(:integer, _), do: {:error, :not_an_integer}

  defp sanitize_field(:boolean, v) when is_boolean(v), do: {:ok, v}
  defp sanitize_field(:boolean, "true"), do: {:ok, true}
  defp sanitize_field(:boolean, "false"), do: {:ok, false}
  defp sanitize_field(:boolean, _), do: {:error, :not_a_boolean}

  defp sanitize_field(type, _), do: {:error, {:unknown_field_type, type}}

  # ── Public helpers ─────────────────────────────────────────────────────────

  @doc "Safe SQL identifier (`{:ok, s}` or `{:error, :empty}`)."
  @spec sql_identifier(String.t()) :: {:ok, String.t()} | {:error, :empty}
  def sql_identifier(input) when is_binary(input) do
    sanitized = String.replace(input, ~r/[^a-zA-Z0-9_]/, "")

    cond do
      sanitized == "" -> {:error, :empty}
      String.match?(sanitized, ~r/\A[0-9]/) -> {:ok, "_" <> sanitized}
      true -> {:ok, sanitized}
    end
  end

  @doc "Safe filename (`{:ok, s}` or `{:error, :empty}`)."
  @spec filename(String.t()) :: {:ok, String.t()} | {:error, :empty}
  def filename(input) when is_binary(input) do
    sanitized =
      input
      |> String.replace("\0", "")
      |> String.replace("/", "")
      |> String.replace("\\", "")
      |> String.replace(~r/[^a-zA-Z0-9_\-.]/, "")
      |> String.replace(~r/\.{2,}/, ".")
      |> String.trim(".")

    if sanitized == "" do
      {:error, :empty}
    else
      {:ok, sanitized}
    end
  end

  # ── Text escaping ──────────────────────────────────────────────────────────

  defp escape_text(v) do
    v
    |> String.replace(~r/[\x00-\x08\x0B\x0C\x0E-\x1F]/, "")
    |> String.trim()
    |> html_escape()
  end

  defp html_escape(s) do
    s
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&#39;")
  end
end
```

## Test harness — implement the `# TODO` test

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
    # TODO
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
