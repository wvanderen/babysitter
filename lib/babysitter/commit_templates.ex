defmodule Babysitter.CommitTemplates do
  @moduledoc """
  Commit message templates with context interpolation.

  Provides templates for common commit scenarios and interpolates
  issue/stage context using TemplateInterpolator.

  ## Triggers

  - `:stage_complete` - After a stage finishes successfully
  - `:validation_pass` - After validation passes
  - `:manual` - Manual commit triggered by user

  ## Placeholders

  All templates support TemplateInterpolator placeholders:
  - `{{issue.id}}` - Issue identifier
  - `{{issue.title}}` - Issue title
  - `{{stage.summary}}` - Stage output summary
  - `{{issue.last_handoff.done}}` - Completed items list
  """

  alias Babysitter.TemplateInterpolator

  @templates %{
    stage_complete: """
    Completed {{issue.id}}: {{stage.summary}}

    Done:
    {{issue.last_handoff.done}}
    """,
    validation_pass: """
    Validated {{issue.id}}: {{stage.summary}}

    All checks passed.
    """,
    manual: """
    {{issue.id}}: {{stage.summary}}

    {{issue.last_handoff.done}}
    """
  }

  @doc """
  Get a template by trigger type.

  ## Examples

      iex> get_template(:stage_complete)
      "Completed {{issue.id}}: ..."

      iex> get_template(:unknown)
      nil
  """
  @spec get_template(atom()) :: String.t() | nil
  def get_template(trigger) when is_atom(trigger) do
    Map.get(@templates, trigger)
  end

  @doc """
  Build a commit message by interpolating context into a template.

  ## Parameters

  - `trigger` - The trigger type atom
  - `issue` - Issue map with id, title, etc.
  - `opts` - Additional context:
    - `:stage` - Stage map with id, name, summary
    - `:session` - Session map
    - `:git` - Git context
    - `:last_handoff` - Handoff context

  ## Examples

      iex> build_message(:stage_complete, %{id: "td-123", title: "Fix"}, stage: %{summary: "Done"})
      "Completed td-123: Done..."
  """
  @spec build_message(atom(), map(), keyword()) :: String.t()
  def build_message(trigger, issue, opts \\ []) do
    case get_template(trigger) do
      nil ->
        raise ArgumentError, "Unknown template trigger: #{trigger}"

      template ->
        build_with_template(template, issue, opts)
    end
  end

  @doc """
  Build a commit message using a custom template.

  ## Parameters

  - `template` - Custom template string with placeholders
  - `issue` - Issue map
  - `opts` - Additional context (same as build_message/3)

  ## Examples

      iex> build_with_template("Issue: {{issue.id}}", %{id: "td-123"}, [])
      "Issue: td-123"
  """
  @spec build_with_template(String.t(), map(), keyword()) :: String.t()
  def build_with_template(template, issue, opts) do
    context = TemplateInterpolator.build_context(issue, opts)
    TemplateInterpolator.interpolate(template, context)
  end

  @doc """
  List available trigger types.

  ## Examples

      iex> triggers()
      [:stage_complete, :validation_pass, :manual]
  """
  @spec triggers() :: [atom()]
  def triggers do
    Map.keys(@templates)
  end

  @doc """
  Return all templates as a map.

  ## Examples

      iex> all_templates()[:stage_complete]
      "Completed {{issue.id}}: ..."
  """
  @spec all_templates() :: %{atom() => String.t()}
  def all_templates do
    @templates
  end
end
