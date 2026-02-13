defmodule Babysitter.Context do
  @moduledoc """
  Context extraction from TD handoffs and issue history.

  Extracts relevant context for prompt interpolation:
  - done: Completed items from last handoff
  - remaining: Todo items from last handoff
  - decisions: Design decisions made
  - uncertain: Items needing clarification
  """

  alias Babysitter.TD.{Client, Handoff}

  @type context :: %{
          issue_id: String.t(),
          done: [String.t()],
          remaining: [String.t()],
          decisions: [String.t()],
          uncertain: [String.t()],
          handoff_count: non_neg_integer(),
          last_handoff_at: NaiveDateTime.t() | nil
        }

  @doc """
  Extract context from the latest handoff for an issue.

  Returns a map with extracted context fields.
  """
  @spec from_handoff(String.t()) :: context()
  def from_handoff(issue_id) do
    handoff = Client.get_latest_handoff(issue_id)

    if handoff do
      %{
        issue_id: issue_id,
        done: Handoff.parse_done(handoff),
        remaining: Handoff.parse_remaining(handoff),
        decisions: Handoff.parse_decisions(handoff),
        uncertain: Handoff.parse_uncertain(handoff),
        handoff_count: count_handoffs(issue_id),
        last_handoff_at: handoff.timestamp
      }
    else
      empty_context(issue_id)
    end
  end

  @doc """
  Extract context from a specific handoff.
  """
  @spec from_handoff_struct(Handoff.t()) :: context()
  def from_handoff_struct(%Handoff{} = handoff) do
    %{
      issue_id: handoff.issue_id,
      done: Handoff.parse_done(handoff),
      remaining: Handoff.parse_remaining(handoff),
      decisions: Handoff.parse_decisions(handoff),
      uncertain: Handoff.parse_uncertain(handoff),
      handoff_count: count_handoffs(handoff.issue_id),
      last_handoff_at: handoff.timestamp
    }
  end

  @doc """
  Build a formatted summary string from context.

  Useful for embedding in prompts.
  """
  @spec summary(context()) :: String.t()
  def summary(context) do
    parts = []

    parts =
      if context.done != [] do
        [
          "## Completed\n" <>
            Enum.map_join(context.done, "\n", fn item -> "- #{item}" end)
          | parts
        ]
      else
        parts
      end

    parts =
      if context.remaining != [] do
        [
          "## Remaining\n" <>
            Enum.map_join(context.remaining, "\n", fn item -> "- #{item}" end)
          | parts
        ]
      else
        parts
      end

    parts =
      if context.decisions != [] do
        [
          "## Decisions Made\n" <>
            Enum.map_join(context.decisions, "\n", fn item -> "- #{item}" end)
          | parts
        ]
      else
        parts
      end

    parts =
      if context.uncertain != [] do
        [
          "## Needs Clarification\n" <>
            Enum.map_join(context.uncertain, "\n", fn item -> "- #{item}" end)
          | parts
        ]
      else
        parts
      end

    if parts == [] do
      "No previous context available."
    else
      Enum.join(Enum.reverse(parts), "\n\n")
    end
  end

  @doc """
  Check if there's any meaningful context.
  """
  @spec has_context?(context()) :: boolean()
  def has_context?(context) do
    context.done != [] or
      context.remaining != [] or
      context.decisions != [] or
      context.uncertain != []
  end

  @doc """
  Merge multiple contexts (e.g., from multiple handoffs).

  Later contexts take precedence for conflicting items.
  """
  @spec merge([context()]) :: context()
  def merge(contexts) when is_list(contexts) do
    if contexts == [] do
      empty_context(nil)
    else
      latest = hd(contexts)

      %{
        issue_id: latest.issue_id,
        done: merge_lists(contexts, :done),
        remaining: merge_lists(contexts, :remaining),
        decisions: merge_lists(contexts, :decisions),
        uncertain: merge_lists(contexts, :uncertain),
        handoff_count: Enum.sum(Enum.map(contexts, & &1.handoff_count)),
        last_handoff_at: latest.last_handoff_at
      }
    end
  end

  @doc """
  Create empty context for an issue.
  """
  @spec empty_context(String.t() | nil) :: context()
  def empty_context(issue_id) do
    %{
      issue_id: issue_id,
      done: [],
      remaining: [],
      decisions: [],
      uncertain: [],
      handoff_count: 0,
      last_handoff_at: nil
    }
  end

  defp count_handoffs(issue_id) do
    Client.get_handoffs(issue_id)
    |> length()
  end

  defp merge_lists(contexts, field) do
    contexts
    |> Enum.flat_map(&Map.get(&1, field, []))
    |> Enum.uniq()
  end
end
