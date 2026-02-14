defmodule Babysitter.TemplateInterpolator do
  @moduledoc """
  Interpolates {{placeholder}} syntax in template strings.

  Supports nested path access like {{issue.last_handoff.done}} and
  list formatting with configurable separators.

  ## Supported Placeholders

  - `{{issue.id}}` - Issue identifier
  - `{{issue.title}}` - Issue title
  - `{{issue.description}}` - Issue description
  - `{{issue.status}}` - Current status
  - `{{issue.priority}}` - Priority level
  - `{{issue.last_handoff.done}}` - List of completed items
  - `{{issue.last_handoff.remaining}}` - List of remaining items
  - `{{issue.last_handoff.decisions}}` - List of decisions
  - `{{issue.last_handoff.uncertain}}` - List of uncertain items
  - `{{stage.id}}` - Stage identifier
  - `{{stage.name}}` - Stage name
  - `{{stage.summary}}` - Stage summary/output
  - `{{session.id}}` - Session identifier
  - `{{git.branch}}` - Current git branch
  - `{{git.commit}}` - Current commit SHA

  ## List Formatting

  Lists are formatted with bullet points by default:
      {{issue.last_handoff.done}}
  Produces:
      - Item 1
      - Item 2

  Custom separators can be specified:
      {{issue.last_handoff.done | join: ", "}}
  """

  @placeholder_regex ~r/\{\{([\w.]+)(?:\s*\|\s*(\w+)(?::\s*([^}]+))?)?\}\}/

  @doc """
  Interpolate placeholders in a template string.

  ## Options

  - `:missing` - How to handle missing values: `:empty` (default), `:keep`, `:raise`
  - `:list_style` - How to format lists: `:bullets` (default), `:plain`

  ## Examples

      iex> interpolate("Issue: {{issue.id}}", %{issue: %{id: "td-123"}})
      "Issue: td-123"

      iex> interpolate("Branch: {{git.branch}}", %{git: %{branch: "main"}})
      "Branch: main"
  """
  @spec interpolate(String.t(), map(), keyword()) :: String.t()
  def interpolate(template, context, opts \\ []) do
    missing = Keyword.get(opts, :missing, :empty)
    list_style = Keyword.get(opts, :list_style, :bullets)

    Regex.replace(@placeholder_regex, template, fn _, path, filter, filter_arg ->
      resolve_placeholder(path, context, missing, list_style, filter, filter_arg)
    end)
  end

  @doc """
  Build a context map from common sources.

  Combines issue, stage, session, and git data into a single context
  suitable for template interpolation.

  ## Parameters

  - `issue` - TD.Issue struct or map with issue data
  - `opts` - Additional context sources:
    - `:stage` - Stage map with id, name, summary
    - `:session` - Session map with id
    - `:git` - Git map with branch, commit
    - `:last_handoff` - Handoff context from Context.from_handoff/1

  ## Examples

      iex> build_context(%{id: "td-123", title: "Fix bug"})
      %{issue: %{id: "td-123", title: "Fix bug", ...}}
  """
  @spec build_context(map() | nil, keyword()) :: map()
  def build_context(issue, opts \\ [])

  def build_context(nil, opts) do
    build_context(%{}, opts)
  end

  def build_context(issue, opts) do
    stage = Keyword.get(opts, :stage, %{})
    session = Keyword.get(opts, :session, %{})
    git = Keyword.get(opts, :git, %{})
    last_handoff = Keyword.get(opts, :last_handoff)

    %{
      issue: build_issue_context(issue, last_handoff),
      stage: build_stage_context(stage),
      session: build_session_context(session),
      git: build_git_context(git)
    }
  end

  defp build_issue_context(issue, nil) do
    %{
      id: Map.get(issue, :id, ""),
      title: Map.get(issue, :title, ""),
      description: Map.get(issue, :description, ""),
      status: Map.get(issue, :status, ""),
      priority: Map.get(issue, :priority, ""),
      type: Map.get(issue, :type, ""),
      labels: parse_labels(Map.get(issue, :labels, "")),
      last_handoff: %{
        done: [],
        remaining: [],
        decisions: [],
        uncertain: []
      }
    }
  end

  defp build_issue_context(issue, handoff_context) do
    %{
      id: Map.get(issue, :id, ""),
      title: Map.get(issue, :title, ""),
      description: Map.get(issue, :description, ""),
      status: Map.get(issue, :status, ""),
      priority: Map.get(issue, :priority, ""),
      type: Map.get(issue, :type, ""),
      labels: parse_labels(Map.get(issue, :labels, "")),
      last_handoff: %{
        done: Map.get(handoff_context, :done, []),
        remaining: Map.get(handoff_context, :remaining, []),
        decisions: Map.get(handoff_context, :decisions, []),
        uncertain: Map.get(handoff_context, :uncertain, [])
      }
    }
  end

  defp build_stage_context(stage) do
    %{
      id: Map.get(stage, :id, ""),
      name: Map.get(stage, :name, ""),
      summary: Map.get(stage, :summary, ""),
      output: Map.get(stage, :output, "")
    }
  end

  defp build_session_context(session) do
    %{
      id: Map.get(session, :id, ""),
      branch: Map.get(session, :branch, "")
    }
  end

  defp build_git_context(git) do
    %{
      branch: Map.get(git, :branch, ""),
      commit: Map.get(git, :commit, ""),
      short_commit: short_sha(Map.get(git, :commit, "")),
      message: Map.get(git, :message, "")
    }
  end

  defp parse_labels(""), do: []
  defp parse_labels(nil), do: []

  defp parse_labels(labels) when is_binary(labels) do
    labels
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp parse_labels(labels) when is_list(labels), do: labels

  defp short_sha(sha) when byte_size(sha) >= 7, do: String.slice(sha, 0, 7)
  defp short_sha(sha), do: sha

  defp resolve_placeholder(path, context, missing, list_style, filter, filter_arg) do
    case get_nested_value(context, String.split(path, ".")) do
      {:ok, value} ->
        format_value(value, list_style, filter, filter_arg)

      :missing ->
        handle_missing(path, missing)
    end
  end

  defp get_nested_value(map, []), do: {:ok, map}

  defp get_nested_value(map, [key | rest]) when is_map(map) do
    atom_key = maybe_to_atom(key)

    cond do
      Map.has_key?(map, key) ->
        get_nested_value(Map.get(map, key), rest)

      Map.has_key?(map, atom_key) ->
        get_nested_value(Map.get(map, atom_key), rest)

      true ->
        :missing
    end
  end

  defp get_nested_value(_, _), do: :missing

  defp maybe_to_atom(string) do
    try do
      String.to_existing_atom(string)
    rescue
      ArgumentError -> string
    end
  end

  defp format_value(value, list_style, nil, nil) do
    do_format_value(value, list_style)
  end

  defp format_value(value, list_style, "join", separator) do
    case value do
      list when is_list(list) ->
        sep = parse_separator(separator)
        Enum.join(list, sep)

      other ->
        do_format_value(other, list_style)
    end
  end

  defp format_value(value, list_style, "first", _) do
    case value do
      [head | _] -> to_string(head)
      [] -> ""
      other -> do_format_value(other, list_style)
    end
  end

  defp format_value(value, list_style, "last", _) do
    case value do
      list when is_list(list) and length(list) > 0 ->
        [last] = Enum.take(list, -1)
        to_string(last)

      [] ->
        ""

      other ->
        do_format_value(other, list_style)
    end
  end

  defp format_value(value, list_style, "count", _) do
    case value do
      list when is_list(list) -> Integer.to_string(length(list))
      other -> do_format_value(other, list_style)
    end
  end

  defp format_value(value, list_style, _, _), do: do_format_value(value, list_style)

  defp parse_separator(sep) do
    sep
    |> String.trim()
    |> unquote_string()
  end

  defp unquote_string("\"" <> rest), do: String.trim_trailing(rest, "\"")
  defp unquote_string("'" <> rest), do: String.trim_trailing(rest, "'")
  defp unquote_string(s), do: s

  defp do_format_value(list, :bullets) when is_list(list) do
    case list do
      [] -> ""
      items -> Enum.map_join(items, "\n", fn item -> "- #{item}" end)
    end
  end

  defp do_format_value(list, :plain) when is_list(list) do
    Enum.join(list, "\n")
  end

  defp do_format_value(value, _) when is_nil(value), do: ""
  defp do_format_value(value, _) when is_binary(value), do: value
  defp do_format_value(value, _) when is_atom(value), do: Atom.to_string(value)
  defp do_format_value(value, _) when is_number(value), do: to_string(value)

  defp do_format_value(%NaiveDateTime{} = dt, _), do: NaiveDateTime.to_string(dt)
  defp do_format_value(%DateTime{} = dt, _), do: DateTime.to_string(dt)
  defp do_format_value(%Date{} = d, _), do: Date.to_string(d)
  defp do_format_value(%Time{} = t, _), do: Time.to_string(t)

  defp do_format_value(map, _) when is_map(map) do
    Jason.encode!(map)
  end

  defp do_format_value(other, _), do: to_string(other)

  defp handle_missing(_path, :empty), do: ""
  defp handle_missing(path, :keep), do: "{{#{path}}}"

  defp handle_missing(path, :raise) do
    raise ArgumentError, "Missing value for placeholder: #{path}"
  end
end
