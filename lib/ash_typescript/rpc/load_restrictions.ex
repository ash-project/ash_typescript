# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.LoadRestrictions do
  @moduledoc """
  Enforcement of an RPC action's `allowed_loads` / `denied_loads` options.

  `normalize/1` turns the DSL spec into pre-normalized path lists once per
  request. `check!/2` is then called by
  `AshTypescript.Rpc.FieldProcessing.FieldSelector` at every point where it
  appends to the Ash load statement, so a load cannot reach the load statement
  without passing the restrictions — there is no separate traversal that could
  disagree with field selection about what is being loaded.

  Paths are lists of internal field names, e.g. `[:comments, :weighted_score]`.
  """

  @type paths :: [[atom()]]
  @type t :: :none | {:allow, paths()} | {:deny, paths()}

  @doc """
  Normalizes `AshTypescript.Manifest.Custom.load_restrictions/1` output into
  pre-normalized path lists.
  """
  @spec normalize(term()) :: t()
  def normalize({:allow, allowed_loads}), do: {:allow, normalize_paths(List.wrap(allowed_loads))}
  def normalize({:deny, denied_loads}), do: {:deny, normalize_paths(List.wrap(denied_loads))}
  def normalize(_), do: :none

  @doc """
  Validates a single load path against the restrictions.

  Throws `{:load_not_allowed, [path]}` or `{:load_denied, [path]}` — the same
  tuples `AshTypescript.Rpc.ErrorBuilder` already handles — so callers inside
  field selection need no extra error plumbing.
  """
  @spec check!([atom()], t()) :: :ok
  def check!(_path, :none), do: :ok

  def check!(path, {:allow, allowed_paths}) do
    if path_allowed?(path, allowed_paths) do
      :ok
    else
      throw({:load_not_allowed, [format_path(path)]})
    end
  end

  def check!(path, {:deny, denied_paths}) do
    if path_denied?(path, denied_paths) do
      throw({:load_denied, [format_path(path)]})
    else
      :ok
    end
  end

  # Normalize restriction paths to a list of path lists
  # For simple atoms: [:user] => [[:user]]
  # For nested specs: [comments: [:todo]] => [[:comments, :todo]] (NOT [:comments])
  #
  # The key distinction:
  # - denied_loads: [:user] - denies user and all children
  # - denied_loads: [comments: [:todo]] - only denies comments.todo, NOT comments itself
  defp normalize_paths(restrictions) when is_list(restrictions) do
    Enum.flat_map(restrictions, fn
      field when is_atom(field) ->
        # Simple atom - this path itself is restricted
        [[field]]

      {field, nested} when is_atom(field) and is_list(nested) ->
        # Nested specification - only the nested paths are restricted
        # NOT the parent field itself
        normalize_paths(nested)
        |> Enum.map(fn nested_path -> [field | nested_path] end)

      _ ->
        []
    end)
  end

  defp normalize_paths(_), do: []

  # Check if a path is allowed by the allowed_loads specification
  # A path is allowed ONLY if:
  # 1. It exactly matches an allowed path, OR
  # 2. It's a prefix of an allowed path (intermediate load needed to reach deeper allowed paths)
  #
  # Note: Unlike denied_loads, we do NOT allow children of allowed paths automatically.
  # If you want to allow user.todos, you must explicitly add [user: [:todos]] to allowed_loads.
  defp path_allowed?(path, allowed_paths) do
    Enum.any?(allowed_paths, fn allowed_path ->
      # Exact match or path is a prefix (intermediate load)
      path == allowed_path or List.starts_with?(allowed_path, path)
    end)
  end

  # Check if a path is denied by the denied_loads specification
  # A path is denied if it matches or starts with a denied path
  defp path_denied?(path, denied_paths) do
    Enum.any?(denied_paths, fn denied_path ->
      # Path is denied if:
      # 1. It exactly matches a denied path, OR
      # 2. It starts with a denied path (loading something under a denied field)
      path == denied_path or List.starts_with?(path, denied_path)
    end)
  end

  defp format_path(path) do
    Enum.map_join(path, ".", &to_string/1)
  end
end
