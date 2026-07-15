defmodule GenTask.PromptsTest do
  # T1.4 (docs/12 §5.3, landed 2026-07-15): the authoring templates. These tests
  # pin the four upgrades so they cannot silently drift out again:
  #   (a) ONE shared harness-rule block used by base AND variation prompts;
  #   (b) exemplar ROTATION — different idea numbers see different worked examples;
  #   (c) register variation is requested explicitly;
  #   (d) the cross-process concurrency axis is demanded of variations.
  use ExUnit.Case, async: true

  alias GenTask.Prompts

  defp base_user(num) do
    {_sys, user} = Prompts.base_task(%{num: num, name: "Some Idea", desc: "Do a thing."})
    user
  end

  defp variations_user do
    base = %{
      "prompt.md" => "p",
      "solution.ex" => "defmodule X do\nend\n",
      "test_harness.exs" => "defmodule XTest do\nend\n"
    }

    {_sys, user} = Prompts.variations(%{num: 7, name: "Idea"}, base, "## catalog", 3, [], [])
    user
  end

  describe "the shared harness-rule block (T1.4a)" do
    test "base and variation prompts carry the SAME rules — no more drift" do
      rules = Prompts.harness_rules()

      for marker <- [
            "LIFECYCLE RULE",
            "CALLBACK RULE",
            "COVERAGE RULE",
            "API SHAPE",
            "use ExUnit.Case, async: false",
            "System.pid()",
            "doctest"
          ] do
        assert rules =~ marker, "shared rules lost #{marker}"
      end

      assert base_user(1) =~ rules
      assert variations_user() =~ rules
    end

    test "the coverage rule forbids untested documented options (the :name-override class)" do
      assert Prompts.harness_rules() =~ "Do not document an\n  option"
      assert Prompts.harness_rules() =~ ":name` override"
    end
  end

  describe "exemplar rotation (T1.4c)" do
    test "different idea numbers see different worked examples, deterministically" do
      examples = for num <- 1..3, do: Prompts.exemplar_for(num)
      assert length(Enum.uniq(examples)) == 3
      assert Prompts.exemplar_for(4) == Prompts.exemplar_for(1)
      assert Prompts.exemplar_for(7) == Prompts.exemplar_for(1)
    end

    test "the rotated exemplar is embedded in the base prompt" do
      {p1, _} = Prompts.exemplar_for(1)
      {p2, _} = Prompts.exemplar_for(2)
      assert base_user(1) =~ String.slice(p1, 0, 60)
      assert base_user(2) =~ String.slice(p2, 0, 60)
      refute base_user(1) =~ String.slice(p2, 0, 60)
    end
  end

  describe "register variation (row 21)" do
    test "the base template explicitly forbids defaulting to the 'Write me' opener" do
      assert base_user(1) =~ "Do not default to opening with \"Write me\""
      assert base_user(1) =~ "Vary the rhetorical register"
    end
  end

  describe "the audit taxonomy checklist (T1.11a)" do
    test "the auditor prompt enumerates the scheduled-work matrix and exactly-once classes" do
      {_sys, user} =
        Prompts.promise_audit(
          %{"prompt.md" => "p", "solution.ex" => "s", "test_harness.exs" => "h"},
          6
        )

      assert user =~ "SCHEDULED-WORK MATRIX"
      assert user =~ "EXACTLY-ONCE"
      assert user =~ "STALENESS"
      assert user =~ "already-queued timer message"
    end
  end

  describe "the cross-process concurrency axis (G-G)" do
    test "variations are required to move at least one variation across processes" do
      user = variations_user()
      assert user =~ "AXIS REQUIREMENT"
      assert user =~ "spawned Tasks"
      assert user =~ "stale"
    end
  end
end
