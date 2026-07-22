defmodule SanitizerTest do
  use ExUnit.Case, async: false

  setup do
    {:ok, pid} = Sanitizer.start_link()
    {:ok, server: pid}
  end

  describe "identifier sanitization + metrics" do
    test "cleans and counts", %{server: s} do
      assert {:ok, "users"} = Sanitizer.sanitize_identifier(s, "us;ers")
      assert {:ok, "_1t"} = Sanitizer.sanitize_identifier(s, "1t")
      assert {:error, :empty} = Sanitizer.sanitize_identifier(s, "!!!")

      m = Sanitizer.metrics(s)
      assert m.identifiers == 3
      assert m.identifiers_blocked == 1
    end
  end

  describe "filename sanitization + metrics" do
    test "cleans traversal and counts", %{server: s} do
      assert {:ok, "etcpasswd"} = Sanitizer.sanitize_filename(s, "../etc/passwd")
      assert {:error, :empty} = Sanitizer.sanitize_filename(s, "/\\")

      m = Sanitizer.metrics(s)
      assert m.filenames == 2
      assert m.filenames_blocked == 1
      assert m.filenames_truncated == 0
    end

    test "truncates to max_filename_length and counts truncations" do
      {:ok, s} = Sanitizer.start_link(max_filename_length: 5)
      assert {:ok, "abcde"} = Sanitizer.sanitize_filename(s, "abcdefghij")
      assert {:ok, "xy"} = Sanitizer.sanitize_filename(s, "xy")

      m = Sanitizer.metrics(s)
      assert m.filenames == 2
      assert m.filenames_truncated == 1
    end
  end

  describe "html stripping + metrics" do
    test "removes script content and counts tags", %{server: s} do
      assert {:ok, "Hello world", n} =
               Sanitizer.strip_html(s, "<b>Hello</b> <script>alert(1)</script>world")

      # <b>, </b>, <script>, </script> = 4 tag tokens in the original
      assert n == 4

      assert {:ok, "plain", _} = Sanitizer.strip_html(s, "<div><p>plain</p></div>")

      m = Sanitizer.metrics(s)
      assert m.html_calls == 2
      assert m.tags_stripped == 4 + 4
    end

    test "no tags means zero stripped", %{server: s} do
      assert {:ok, "just text", 0} = Sanitizer.strip_html(s, "just text")
    end
  end

  describe "reset_metrics" do
    test "zeroes everything", %{server: s} do
      Sanitizer.sanitize_identifier(s, "ok")
      Sanitizer.strip_html(s, "<b>x</b>")
      assert :ok = Sanitizer.reset_metrics(s)

      m = Sanitizer.metrics(s)
      assert m.identifiers == 0
      assert m.tags_stripped == 0
      assert m.html_calls == 0
    end
  end

  describe "concurrency" do
    test "metrics stay exact under many concurrent callers", %{server: s} do
      valid =
        for _ <- 1..100 do
          Task.async(fn -> Sanitizer.sanitize_identifier(s, "users") end)
        end

      invalid =
        for _ <- 1..50 do
          Task.async(fn -> Sanitizer.sanitize_identifier(s, "###") end)
        end

      files =
        for _ <- 1..40 do
          Task.async(fn -> Sanitizer.sanitize_filename(s, "../a/b") end)
        end

      Enum.each(valid ++ invalid ++ files, &Task.await/1)

      m = Sanitizer.metrics(s)
      assert m.identifiers == 150
      assert m.identifiers_blocked == 50
      assert m.filenames == 40
      assert m.filenames_blocked == 0
    end
  end
end
