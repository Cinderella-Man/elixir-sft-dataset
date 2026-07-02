defmodule GenTask.ReplyTest do
  use ExUnit.Case, async: true

  alias GenTask.Reply

  @harness """
  defmodule FooTest do
    use ExUnit.Case, async: false
    test "works", do: assert Foo.x() == 1
  end
  """

  @solution """
  defmodule Foo do
    def x, do: 1
  end
  """

  describe "sanitize_file_body/1" do
    test "strips a wrapping ```elixir fence" do
      body = "```elixir\ndefmodule Foo do\n  def x, do: 1\nend\n```"
      assert Reply.sanitize_file_body(body) == "defmodule Foo do\n  def x, do: 1\nend"
    end

    test "strips a bare ``` fence with no language word" do
      body = "```\nhello\nworld\n```"
      assert Reply.sanitize_file_body(body) == "hello\nworld"
    end

    test "is a no-op on an already-clean body" do
      assert Reply.sanitize_file_body(@solution) == @solution
    end

    test "does not strip an unbalanced leading fence" do
      body = "```elixir\ndefmodule Foo do\nend"
      assert Reply.sanitize_file_body(body) == body
    end
  end

  describe "parse/1" do
    test "returns a path => sanitized-body map, stripping fences per file" do
      text = """
      Here you go:
      <file path="solution.ex">
      ```elixir
      defmodule Foo do
        def x, do: 1
      end
      ```
      </file>
      <file path="prompt.md">
      Implement Foo.x/0.
      </file>
      """

      files = Reply.parse(text)

      assert files["solution.ex"] == "defmodule Foo do\n  def x, do: 1\nend"
      assert files["prompt.md"] == "Implement Foo.x/0."
    end

    test "keeps a clean body untouched" do
      text = ~s(<file path="solution.ex">\n#{@solution}</file>)
      assert Reply.parse(text)["solution.ex"] =~ "def x, do: 1"
      refute Reply.parse(text)["solution.ex"] =~ "```"
    end
  end

  describe "validate_task/1" do
    test "accepts prompt.md + a proper ...Test harness" do
      files = %{"prompt.md" => "Do it.", "test_harness.exs" => @harness}
      assert Reply.validate_task(files) == :ok
    end

    test "rejects a missing prompt.md" do
      assert {:error, msg} = Reply.validate_task(%{"test_harness.exs" => @harness})
      assert msg =~ "prompt.md"
    end

    test "rejects a harness without a Test module" do
      bad = "defmodule Foo do\n  use ExUnit.Case\nend"
      assert {:error, msg} = Reply.validate_task(%{"prompt.md" => "x", "test_harness.exs" => bad})
      assert msg =~ "Test"
    end

    test "rejects a harness that does not use ExUnit.Case" do
      bad = "defmodule FooTest do\nend"

      assert {:error, msg} =
               Reply.validate_task(%{"prompt.md" => "x", "test_harness.exs" => bad})

      assert msg =~ "ExUnit.Case"
    end
  end

  describe "validate_answer/1" do
    test "accepts a non-empty solution with a defmodule" do
      assert Reply.validate_answer(%{"solution.ex" => @solution}) == :ok
    end

    test "rejects a solution with no defmodule" do
      assert {:error, msg} = Reply.validate_answer(%{"solution.ex" => "x = 1"})
      assert msg =~ "defmodule"
    end

    test "rejects an empty solution" do
      assert {:error, _} = Reply.validate_answer(%{"solution.ex" => "   "})
    end
  end

  describe "validate_fix/1" do
    test "accepts a solution-only fix" do
      assert Reply.validate_fix(%{"solution.ex" => @solution}) == :ok
    end

    test "accepts a harness-only fix" do
      assert Reply.validate_fix(%{"test_harness.exs" => @harness}) == :ok
    end

    test "rejects a fix that returns prompt.md" do
      assert {:error, msg} =
               Reply.validate_fix(%{"prompt.md" => "x", "solution.ex" => @solution})

      assert msg =~ "prompt.md"
    end

    test "rejects a fix with neither solution nor harness" do
      assert {:error, msg} = Reply.validate_fix(%{"notes.txt" => "hi"})
      assert msg =~ "at least one"
    end

    test "rejects a fix whose harness is malformed" do
      assert {:error, msg} =
               Reply.validate_fix(%{"test_harness.exs" => "defmodule Foo do\nend"})

      assert msg =~ "Test"
    end
  end

  describe "validate_variations/1" do
    test "accepts three complete path-prefixed triplets + idea entries" do
      files =
        Enum.flat_map(1..3, fn n ->
          [
            {"v#{n}/prompt.md", "Do #{n}."},
            {"v#{n}/test_harness.exs", @harness},
            {"v#{n}/solution.ex", @solution},
            {"v#{n}/idea.md", "### Task 1 - V#{n} - Variant #{n}\nDesc."}
          ]
        end)
        |> Map.new()

      assert Reply.validate_variations(files) == :ok
    end

    test "rejects when a variation is missing a file" do
      files = %{
        "v1/prompt.md" => "x",
        "v1/test_harness.exs" => @harness,
        "v1/solution.ex" => @solution
        # missing v1/idea.md
      }

      assert {:error, msg} = Reply.validate_variations(files)
      assert msg =~ "v1/idea.md"
    end
  end

  describe "validate_fim/1" do
    @fim_prompt """
    Fill in the missing function.

    ```elixir
    defmodule Foo do
      def x do
        # TODO: implement
      end
    end
    ```
    """

    test "accepts prompt.md with a fenced elixir skeleton + TODO, plus solution.ex" do
      files = %{"prompt.md" => @fim_prompt, "solution.ex" => "def x, do: 1"}
      assert Reply.validate_fim(files) == :ok
    end

    test "rejects a prompt.md with no fenced elixir skeleton" do
      files = %{"prompt.md" => "Just implement it. # TODO", "solution.ex" => "def x, do: 1"}
      assert {:error, msg} = Reply.validate_fim(files)
      assert msg =~ "elixir"
    end

    test "rejects a skeleton with no TODO marker" do
      prompt = "```elixir\ndefmodule Foo do\nend\n```"
      files = %{"prompt.md" => prompt, "solution.ex" => "def x, do: 1"}
      assert {:error, msg} = Reply.validate_fim(files)
      assert msg =~ "TODO"
    end
  end
end
