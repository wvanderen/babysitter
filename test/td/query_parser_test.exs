defmodule Babysitter.TD.QueryParserTest do
  use ExUnit.Case, async: true

  alias Babysitter.TD.QueryParser

  describe "parse/1 - basic comparisons" do
    test "parses simple equality" do
      assert {:ok, {:comparison, "status", :=, "open"}} = QueryParser.parse("status = open")
    end

    test "parses equality with ==" do
      assert {:ok, {:comparison, "status", :==, "open"}} = QueryParser.parse("status == open")
    end

    test "parses inequality" do
      assert {:ok, {:comparison, "status", :!=, "closed"}} = QueryParser.parse("status != closed")
    end

    test "parses less than" do
      assert {:ok, {:comparison, "priority", :<, "3"}} = QueryParser.parse("priority < 3")
    end

    test "parses greater than" do
      assert {:ok, {:comparison, "priority", :>, "1"}} = QueryParser.parse("priority > 1")
    end

    test "parses less than or equal" do
      assert {:ok, {:comparison, "points", :<=, "5"}} = QueryParser.parse("points <= 5")
    end

    test "parses greater than or equal" do
      assert {:ok, {:comparison, "points", :>=, "1"}} = QueryParser.parse("points >= 1")
    end

    test "parses like operator" do
      assert {:ok, {:comparison, "title", :like, "bug"}} = QueryParser.parse("title ~ bug")
    end
  end

  describe "parse/1 - quoted strings" do
    test "parses double-quoted strings" do
      assert {:ok, {:comparison, "title", :=, "hello world"}} =
               QueryParser.parse(~s(title = "hello world"))
    end

    test "parses single-quoted strings" do
      assert {:ok, {:comparison, "title", :=, "hello world"}} =
               QueryParser.parse("title = 'hello world'")
    end

    test "handles escaped quotes in double-quoted strings" do
      assert {:ok, {:comparison, "title", :=, ~s(it's "nice")}} =
               QueryParser.parse(~s(title = "it's \\"nice\\""))
    end
  end

  describe "parse/1 - boolean operators" do
    test "parses AND expression" do
      assert {:ok,
              {:and, {:comparison, "status", :=, "open"}, {:comparison, "type", :=, "feature"}}} =
               QueryParser.parse("status = open AND type = feature")
    end

    test "parses OR expression" do
      assert {:ok,
              {:or, {:comparison, "status", :=, "open"},
               {:comparison, "status", :=, "in_progress"}}} =
               QueryParser.parse("status = open OR status = in_progress")
    end

    test "parses NOT expression" do
      assert {:ok, {:not, {:comparison, "status", :=, "closed"}}} =
               QueryParser.parse("NOT status = closed")
    end

    test "parses chained AND expressions" do
      assert {:ok, {:and, _, {:and, _, _}}} =
               QueryParser.parse("a = 1 AND b = 2 AND c = 3")
    end

    test "parses mixed AND/OR with proper precedence" do
      {:ok, ast} = QueryParser.parse("a = 1 OR b = 2 AND c = 3")
      assert {:or, {:comparison, "a", :=, "1"}, {:and, _, _}} = ast
    end
  end

  describe "parse/1 - grouping" do
    test "parses parenthesized expression" do
      assert {:ok, {:or, {:and, _, _}, {:comparison, "c", :=, "3"}}} =
               QueryParser.parse("(a = 1 AND b = 2) OR c = 3")
    end

    test "parses nested parentheses" do
      assert {:ok, {:or, _, {:or, _, _}}} =
               QueryParser.parse("a = 1 OR (b = 2 OR (c = 3 OR d = 4))")
    end
  end

  describe "parse/1 - errors" do
    test "returns error for empty input" do
      assert {:error, _} = QueryParser.parse("")
    end

    test "returns error for incomplete expression" do
      assert {:error, _} = QueryParser.parse("status =")
    end

    test "returns error for missing operator" do
      assert {:error, _} = QueryParser.parse("status open")
    end

    test "returns error for unclosed parenthesis" do
      assert {:error, _} = QueryParser.parse("(status = open")
    end
  end

  describe "to_sql/1" do
    test "converts simple comparison to SQL" do
      {:ok, ast} = QueryParser.parse("status = open")
      assert QueryParser.to_sql(ast) == "status = 'open'"
    end

    test "converts LIKE comparison" do
      {:ok, ast} = QueryParser.parse("title ~ test")
      assert QueryParser.to_sql(ast) == "title LIKE 'test'"
    end

    test "converts AND expression" do
      {:ok, ast} = QueryParser.parse("status = open AND priority = P0")
      assert QueryParser.to_sql(ast) == "(status = 'open' AND priority = 'P0')"
    end

    test "converts OR expression" do
      {:ok, ast} = QueryParser.parse("a = 1 OR b = 2")
      assert QueryParser.to_sql(ast) == "(a = '1' OR b = '2')"
    end

    test "converts NOT expression" do
      {:ok, ast} = QueryParser.parse("NOT status = closed")
      assert QueryParser.to_sql(ast) == "NOT (status = 'closed')"
    end

    test "escapes single quotes in values" do
      {:ok, ast} = QueryParser.parse("title = 'it''s a test'")
      assert QueryParser.to_sql(ast) == "title = 'it''s a test'"
    end
  end

  describe "to_ecto/1" do
    alias Babysitter.TD.{Issue, Repo}
    import Ecto.Query

    setup do
      now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

      Repo.insert!(%Issue{
        id: "td-qp-test-1",
        title: "Test Issue Query Parser",
        status: "open",
        type: "task",
        priority: "P0",
        created_at: now,
        updated_at: now
      })

      Repo.insert!(%Issue{
        id: "td-qp-test-2",
        title: "Another Test",
        status: "in_review",
        type: "epic",
        priority: "P1",
        created_at: now,
        updated_at: now
      })

      on_exit(fn ->
        Repo.delete_all(Issue)
      end)

      :ok
    end

    test "filters by single field equality" do
      {:ok, ast} = QueryParser.parse("status = open")
      dynamic = QueryParser.to_ecto(ast)

      results = from(i in Issue, where: ^dynamic) |> Repo.all()
      assert length(results) == 1
      assert hd(results).id == "td-qp-test-1"
    end

    test "filters with AND condition" do
      {:ok, ast} = QueryParser.parse("status = open AND priority = P0")
      dynamic = QueryParser.to_ecto(ast)

      results = from(i in Issue, where: ^dynamic) |> Repo.all()
      assert length(results) == 1
      assert hd(results).id == "td-qp-test-1"
    end

    test "filters with OR condition" do
      {:ok, ast} = QueryParser.parse("priority = P0 OR priority = P1")
      dynamic = QueryParser.to_ecto(ast)

      results = from(i in Issue, where: ^dynamic) |> Repo.all()
      assert length(results) == 2
    end

    test "filters with NOT condition" do
      {:ok, ast} = QueryParser.parse("NOT status = open")
      dynamic = QueryParser.to_ecto(ast)

      results = from(i in Issue, where: ^dynamic) |> Repo.all()
      assert length(results) == 1
      assert hd(results).status != "open"
    end

    test "filters with LIKE pattern" do
      {:ok, ast} = QueryParser.parse("title ~ Query")
      dynamic = QueryParser.to_ecto(ast)

      results = from(i in Issue, where: ^dynamic) |> Repo.all()
      assert length(results) == 1
      assert String.contains?(hd(results).title, "Query")
    end

    test "filters with combined AND and OR" do
      {:ok, ast} = QueryParser.parse("status = open AND (priority = P0 OR priority = P1)")
      dynamic = QueryParser.to_ecto(ast)

      results = from(i in Issue, where: ^dynamic) |> Repo.all()
      assert length(results) == 1
    end

    test "filters with inequality operators" do
      {:ok, ast} = QueryParser.parse("status != closed")
      dynamic = QueryParser.to_ecto(ast)

      results = from(i in Issue, where: ^dynamic) |> Repo.all()
      assert length(results) == 2
    end
  end

  describe "parse/1 - complex expressions" do
    test "parses deeply nested expressions" do
      assert {:ok, _} = QueryParser.parse("((a = 1 OR b = 2) AND c = 3) OR d = 4")
    end

    test "parses multiple NOT operators" do
      assert {:ok, {:not, {:not, _}}} = QueryParser.parse("NOT NOT a = 1")
    end

    test "parses mixed boolean with proper precedence" do
      {:ok, ast} = QueryParser.parse("a = 1 OR b = 2 AND c = 3")
      assert {:or, {:comparison, "a", :=, "1"}, {:and, _, _}} = ast
    end
  end

  describe "to_sql/1 - edge cases" do
    test "handles complex nested expressions" do
      {:ok, ast} = QueryParser.parse("(a = 1 AND b = 2) OR (c = 3 AND d = 4)")
      sql = QueryParser.to_sql(ast)
      assert sql =~ "AND"
      assert sql =~ "OR"
    end
  end
end
