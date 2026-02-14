defmodule Babysitter.TD.QueryParser do
  @moduledoc """
  Recursive descent parser for TDQ (TD Query) syntax.

  Parses queries like `status = open AND type = feature` into AST,
  then converts to SQL WHERE clauses or Ecto dynamic queries.

  ## Supported Operators

  Comparison: =, !=, <, >, <=, >=, ~ (LIKE pattern)
  Boolean: AND, OR, NOT
  Grouping: parentheses
  Values: quoted strings, numbers, bare identifiers

  ## Examples

      iex> QueryParser.parse("status = open")
      {:ok, {:comparison, "status", :=, "open"}}

      iex> QueryParser.parse("status = open AND priority = P0")
      {:ok, {:and, {:comparison, "status", :=, "open"}, {:comparison, "priority", :=, "P0"}}}

      iex> QueryParser.to_sql(parsed)
      "status = 'open' AND priority = 'P0'"
  """

  defmodule Lexer do
    @moduledoc false

    def tokenize(input) when is_binary(input) do
      input
      |> String.trim()
      |> String.to_charlist()
      |> tokenize_acc([], [])
    end

    defp tokenize_acc([], [], tokens), do: {:ok, Enum.reverse(tokens)}

    defp tokenize_acc([], buffer, tokens) do
      tokens = flush_buffer(buffer, tokens)
      {:ok, Enum.reverse(tokens)}
    end

    defp tokenize_acc([?( | rest], buffer, tokens) do
      tokens = flush_buffer(buffer, tokens)
      tokenize_acc(rest, [], [{:lparen, :lparen} | tokens])
    end

    defp tokenize_acc([?) | rest], buffer, tokens) do
      tokens = flush_buffer(buffer, tokens)
      tokenize_acc(rest, [], [{:rparen, :rparen} | tokens])
    end

    defp tokenize_acc([c | rest], buffer, tokens) when c in ~c" \t\n\r" do
      tokens = flush_buffer(buffer, tokens)
      tokenize_acc(rest, [], tokens)
    end

    defp tokenize_acc([?=, ?= | rest], buffer, tokens) do
      tokens = flush_buffer(buffer, tokens)
      tokenize_acc(rest, [], [{:op, :==} | tokens])
    end

    defp tokenize_acc([?= | rest], buffer, tokens) do
      tokens = flush_buffer(buffer, tokens)
      tokenize_acc(rest, [], [{:op, :=} | tokens])
    end

    defp tokenize_acc([?!, ?= | rest], buffer, tokens) do
      tokens = flush_buffer(buffer, tokens)
      tokenize_acc(rest, [], [{:op, :!=} | tokens])
    end

    defp tokenize_acc([?<, ?= | rest], buffer, tokens) do
      tokens = flush_buffer(buffer, tokens)
      tokenize_acc(rest, [], [{:op, :<=} | tokens])
    end

    defp tokenize_acc([?>, ?= | rest], buffer, tokens) do
      tokens = flush_buffer(buffer, tokens)
      tokenize_acc(rest, [], [{:op, :>=} | tokens])
    end

    defp tokenize_acc([?< | rest], buffer, tokens) do
      tokens = flush_buffer(buffer, tokens)
      tokenize_acc(rest, [], [{:op, :<} | tokens])
    end

    defp tokenize_acc([?> | rest], buffer, tokens) do
      tokens = flush_buffer(buffer, tokens)
      tokenize_acc(rest, [], [{:op, :>} | tokens])
    end

    defp tokenize_acc([?~ | rest], buffer, tokens) do
      tokens = flush_buffer(buffer, tokens)
      tokenize_acc(rest, [], [{:op, :like} | tokens])
    end

    defp tokenize_acc([?" | rest], buffer, tokens) do
      tokens = flush_buffer(buffer, tokens)
      {string, rest} = read_string(rest, [])
      tokenize_acc(rest, [], [{string, :string} | tokens])
    end

    defp tokenize_acc([?' | rest], buffer, tokens) do
      tokens = flush_buffer(buffer, tokens)
      {string, rest} = read_single_string(rest, [])
      tokenize_acc(rest, [], [{string, :string} | tokens])
    end

    defp tokenize_acc([c | rest], buffer, tokens) do
      tokenize_acc(rest, [c | buffer], tokens)
    end

    defp flush_buffer([], tokens), do: tokens

    defp flush_buffer(buffer, tokens) do
      word = bare_word(Enum.reverse(buffer))

      token =
        case String.upcase(word) do
          "AND" -> {:and, :and}
          "OR" -> {:or, :or}
          "NOT" -> {:not, :not}
          _ -> {word, :word}
        end

      [token | tokens]
    end

    defp bare_word(charlist), do: to_string(charlist)

    defp read_string([?" | rest], acc), do: {to_string(Enum.reverse(acc)), rest}
    defp read_string([?\\, c | rest], acc), do: read_string(rest, [c | acc])
    defp read_string([c | rest], acc), do: read_string(rest, [c | acc])
    defp read_string([], acc), do: {to_string(Enum.reverse(acc)), []}

    defp read_single_string([?', ?' | rest], acc), do: read_single_string(rest, [?' | acc])
    defp read_single_string([?' | rest], acc), do: {to_string(Enum.reverse(acc)), rest}
    defp read_single_string([?\\, c | rest], acc), do: read_single_string(rest, [c | acc])
    defp read_single_string([c | rest], acc), do: read_single_string(rest, [c | acc])
    defp read_single_string([], acc), do: {to_string(Enum.reverse(acc)), []}
  end

  @type ast ::
          {:comparison, String.t(), atom(), value()}
          | {:and, ast, ast}
          | {:or, ast, ast}
          | {:not, ast}

  @type value :: String.t() | number()

  @doc """
  Parse a TDQ query string into an AST.

  ## Examples

      iex> QueryParser.parse("status = open")
      {:ok, {:comparison, "status", :=, "open"}}

      iex> QueryParser.parse("priority < 3")
      {:ok, {:comparison, "priority", :<, "3"}}
  """
  @spec parse(String.t()) :: {:ok, ast()} | {:error, String.t()}
  def parse(input) when is_binary(input) do
    case Lexer.tokenize(input) do
      {:ok, tokens} -> parse_tokens(tokens)
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_tokens(tokens) do
    case parse_or(tokens) do
      {:ok, ast, []} ->
        {:ok, ast}

      {:ok, _ast, remaining} ->
        {:error, "Unexpected tokens after expression: #{inspect(remaining)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_or(tokens) do
    case parse_and(tokens) do
      {:ok, left, [{:or, :or} | rest]} ->
        case parse_or(rest) do
          {:ok, right, rest2} -> {:ok, {:or, left, right}, rest2}
          error -> error
        end

      result ->
        result
    end
  end

  defp parse_and(tokens) do
    case parse_not(tokens) do
      {:ok, left, [{:and, :and} | rest]} ->
        case parse_and(rest) do
          {:ok, right, rest2} -> {:ok, {:and, left, right}, rest2}
          error -> error
        end

      result ->
        result
    end
  end

  defp parse_not([{:not, :not} | rest]) do
    case parse_not(rest) do
      {:ok, inner, rest2} -> {:ok, {:not, inner}, rest2}
      error -> error
    end
  end

  defp parse_not(tokens), do: parse_primary(tokens)

  defp parse_primary([{:lparen, :lparen} | rest]) do
    case parse_or(rest) do
      {:ok, ast, [{:rparen, :rparen} | rest2]} -> {:ok, ast, rest2}
      {:ok, _ast, _rest} -> {:error, "Missing closing parenthesis"}
      error -> error
    end
  end

  defp parse_primary([{field, :word}, {:op, op}, {value, type} | rest])
       when type in [:word, :string] do
    {:ok, {:comparison, field, op, value}, rest}
  end

  defp parse_primary([{_field, :word}, {:op, _op} | _rest]) do
    {:error, "Expected value after operator"}
  end

  defp parse_primary([]) do
    {:error, "Unexpected end of input"}
  end

  defp parse_primary([token | _]) do
    {:error, "Unexpected token: #{inspect(token)}"}
  end

  @doc """
  Convert parsed AST to SQL WHERE clause string.

  ## Examples

      iex> QueryParser.to_sql({:comparison, "status", :=, "open"})
      "status = 'open'"
  """
  @spec to_sql(ast()) :: String.t()
  def to_sql(ast) do
    do_to_sql(ast)
  end

  defp do_to_sql({:comparison, field, op, value}) do
    op_str = sql_operator(op)
    val_str = sql_value(value)
    "#{field} #{op_str} #{val_str}"
  end

  defp do_to_sql({:and, left, right}) do
    "(#{do_to_sql(left)} AND #{do_to_sql(right)})"
  end

  defp do_to_sql({:or, left, right}) do
    "(#{do_to_sql(left)} OR #{do_to_sql(right)})"
  end

  defp do_to_sql({:not, inner}) do
    "NOT (#{do_to_sql(inner)})"
  end

  defp sql_operator(:==), do: "=="
  defp sql_operator(:=), do: "="
  defp sql_operator(:!=), do: "!="
  defp sql_operator(:<), do: "<"
  defp sql_operator(:>), do: ">"
  defp sql_operator(:<=), do: "<="
  defp sql_operator(:>=), do: ">="
  defp sql_operator(:like), do: "LIKE"

  defp sql_value(value) when is_binary(value) do
    escaped = String.replace(value, "'", "''")
    "'#{escaped}'"
  end

  defp sql_value(value) when is_number(value), do: to_string(value)

  @doc """
  Convert parsed AST to Ecto dynamic query.

  ## Examples

      iex> dynamic = QueryParser.to_ecto({:comparison, "status", :=, "open"})
      iex> from(i in Issue, where: ^dynamic) |> Repo.all()
  """
  @spec to_ecto(ast()) :: Ecto.Query.dynamic_expr()
  def to_ecto(ast) do
    import Ecto.Query
    do_to_ecto(ast)
  end

  defp do_to_ecto({:comparison, field, op, value}) do
    import Ecto.Query
    build_comparison(field, op, value)
  end

  defp do_to_ecto({:and, left, right}) do
    import Ecto.Query
    left_dyn = do_to_ecto(left)
    right_dyn = do_to_ecto(right)
    dynamic([i], ^left_dyn and ^right_dyn)
  end

  defp do_to_ecto({:or, left, right}) do
    import Ecto.Query
    left_dyn = do_to_ecto(left)
    right_dyn = do_to_ecto(right)
    dynamic([i], ^left_dyn or ^right_dyn)
  end

  defp do_to_ecto({:not, inner}) do
    import Ecto.Query
    inner_dyn = do_to_ecto(inner)
    dynamic([i], not (^inner_dyn))
  end

  defp build_comparison(field, op, value) do
    import Ecto.Query
    field_atom = String.to_existing_atom(field)

    case op do
      := -> dynamic([i], field(i, ^field_atom) == ^value)
      :== -> dynamic([i], field(i, ^field_atom) == ^value)
      :!= -> dynamic([i], field(i, ^field_atom) != ^value)
      :< -> dynamic([i], field(i, ^field_atom) < ^value)
      :> -> dynamic([i], field(i, ^field_atom) > ^value)
      :<= -> dynamic([i], field(i, ^field_atom) <= ^value)
      :>= -> dynamic([i], field(i, ^field_atom) >= ^value)
      :like -> dynamic([i], like(field(i, ^field_atom), ^"%#{value}%"))
    end
  end
end
