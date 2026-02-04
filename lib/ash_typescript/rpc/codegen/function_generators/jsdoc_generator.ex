# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.Codegen.FunctionGenerators.JsdocGenerator do
  @moduledoc """
  Generates JSDoc comments for RPC functions.

  Provides IDE discoverability by adding documentation with metadata tags
  that describe the action type, resource, internal action name, and namespace.
  """

  alias AshTypescript.Helpers

  @doc """
  Generates a JSDoc comment for an RPC function.

  ## Parameters
  - `resource` - The Ash resource module
  - `action` - The Ash action struct
  - `rpc_action` - The RPC action configuration
  - `opts` - Options including:
    - `:namespace` - The resolved namespace for this action (optional)

  ## Returns
  A string containing the JSDoc comment block.

  ## Example Output

  Default (relative paths):

      /**
       * List all users
       *
       * @ashActionType :read
       * @ashResource MyApp.User
       * @ashAction :list
       * @ashActionDef lib/my_app/resources/user.ex
       * @rpcActionDef lib/my_app/domain.ex
       * @namespace users
       * @see createUser
       * @deprecated Use listUsersV2 instead
       */

  With `:source_path_prefix` set to "backend" (for monorepos):

      /**
       * List all users
       *
       * @ashActionType :read
       * @ashResource MyApp.User
       * @ashAction :list
       * @ashActionDef backend/lib/my_app/resources/user.ex
       * @rpcActionDef backend/lib/my_app/domain.ex
       * @namespace users
       * @see createUser
       * @deprecated Use listUsersV2 instead
       */
  """
  def generate_jsdoc(resource, action, rpc_action, opts \\ []) do
    namespace = Keyword.get(opts, :namespace)
    resource_name = resource |> Module.split() |> List.last()
    include_internals? = AshTypescript.Rpc.add_ash_internals_to_jsdoc?()

    description = build_description(rpc_action, action, resource_name, include_internals?)

    lines = [
      "/**",
      " * #{description}",
      " *",
      " * @ashActionType :#{action.type}"
    ]

    lines =
      if include_internals? do
        lines ++
          [" * @ashResource #{inspect(resource)}", " * @ashAction :#{rpc_action.action}"] ++
          build_ash_action_def_tag(action) ++
          build_rpc_action_def_tag(rpc_action)
      else
        lines
      end

    lines = if namespace, do: lines ++ [" * @namespace #{namespace}"], else: lines
    lines = lines ++ build_see_tags(rpc_action)
    lines = lines ++ build_deprecated_tag(rpc_action)

    (lines ++ [" */"]) |> Enum.join("\n")
  end

  @doc """
  Generates a JSDoc comment for a validation function.

  ## Parameters
  - `resource` - The Ash resource module
  - `action` - The Ash action struct
  - `rpc_action` - The RPC action configuration
  - `opts` - Options including:
    - `:namespace` - The resolved namespace for this action (optional)

  ## Returns
  A string containing the JSDoc comment block.
  """
  def generate_validation_jsdoc(resource, action, rpc_action, opts \\ []) do
    namespace = Keyword.get(opts, :namespace)
    resource_name = resource |> Module.split() |> List.last()
    include_internals? = AshTypescript.Rpc.add_ash_internals_to_jsdoc?()

    description =
      build_validation_description(rpc_action, action, resource_name, include_internals?)

    lines = [
      "/**",
      " * #{description}",
      " *",
      " * @ashActionType :#{action.type}"
    ]

    lines =
      if include_internals? do
        lines ++
          [" * @ashResource #{inspect(resource)}", " * @ashAction :#{rpc_action.action}"] ++
          build_ash_action_def_tag(action) ++
          build_rpc_action_def_tag(rpc_action)
      else
        lines
      end

    lines = lines ++ [" * @validation true"]
    lines = if namespace, do: lines ++ [" * @namespace #{namespace}"], else: lines
    lines = lines ++ build_deprecated_tag(rpc_action)

    (lines ++ [" */"]) |> Enum.join("\n")
  end

  @doc """
  Generates a JSDoc comment for a typed query.

  ## Parameters
  - `typed_query` - The typed query configuration
  - `resource` - The Ash resource module

  ## Returns
  A string containing the JSDoc comment block.
  """
  def generate_typed_query_jsdoc(typed_query, resource) do
    resource_name = resource |> Module.split() |> List.last()
    include_internals? = AshTypescript.Rpc.add_ash_internals_to_jsdoc?()

    description = build_typed_query_description(typed_query, resource_name)

    lines = [
      "/**",
      " * #{description}",
      " *",
      " * @typedQuery true"
    ]

    lines =
      if include_internals? do
        lines ++ [" * @ashResource #{inspect(resource)}"]
      else
        lines
      end

    (lines ++ [" */"]) |> Enum.join("\n")
  end

  defp build_description(rpc_action, action, resource_name, include_internals?) do
    rpc_description = Map.get(rpc_action, :description)
    action_description = Map.get(action, :description)

    cond do
      # RPC action description takes highest priority (always shown when set)
      is_binary(rpc_description) and rpc_description != "" ->
        rpc_description

      # Action description is shown only when exposing internals
      include_internals? and is_binary(action_description) and action_description != "" ->
        action_description

      # Fall back to default description
      true ->
        default_description(action.type, resource_name)
    end
  end

  defp build_validation_description(rpc_action, action, resource_name, include_internals?) do
    main_description = build_description(rpc_action, action, resource_name, include_internals?)
    "Validate: #{main_description}"
  end

  defp build_typed_query_description(typed_query, resource_name) do
    description = Map.get(typed_query, :description)

    if is_binary(description) and description != "" do
      description
    else
      "Typed query for #{resource_name}"
    end
  end

  defp build_see_tags(rpc_action) do
    see_list = Map.get(rpc_action, :see) || []

    Enum.map(see_list, fn action_name ->
      " * @see #{Helpers.format_output_field(action_name)}"
    end)
  end

  defp build_deprecated_tag(rpc_action) do
    case Map.get(rpc_action, :deprecated) do
      nil ->
        []

      false ->
        []

      true ->
        [" * @deprecated"]

      message when is_binary(message) ->
        [" * @deprecated #{message}"]
    end
  end

  defp default_description(:read, resource_name), do: "Read #{resource_name} records"
  defp default_description(:create, resource_name), do: "Create a new #{resource_name}"
  defp default_description(:update, resource_name), do: "Update an existing #{resource_name}"
  defp default_description(:destroy, resource_name), do: "Delete a #{resource_name}"

  defp default_description(:action, resource_name),
    do: "Execute generic action on #{resource_name}"

  defp build_ash_action_def_tag(action) do
    case get_source_location(action) do
      nil -> []
      location -> [" * @ashActionDef #{location}"]
    end
  end

  defp build_rpc_action_def_tag(rpc_action) do
    case get_source_location(rpc_action) do
      nil -> []
      location -> [" * @rpcActionDef #{location}"]
    end
  end

  defp get_source_location(entity) do
    with %{__spark_metadata__: %{anno: anno}} when is_list(anno) <- entity,
         file when is_list(file) <- Keyword.get(anno, :file) do
      file_path = to_string(file)
      format_source_location(file_path)
    else
      _ -> nil
    end
  end

  defp format_source_location(absolute_path) do
    relative_path = make_relative_path(absolute_path)

    case Application.get_env(:ash_typescript, :source_path_prefix) do
      nil ->
        relative_path

      prefix when is_binary(prefix) ->
        # Prefix with base path for monorepo setups
        normalized_prefix = String.trim_trailing(prefix, "/")
        "#{normalized_prefix}/#{relative_path}"
    end
  end

  defp make_relative_path(absolute_path) do
    case File.cwd() do
      {:ok, cwd} ->
        if String.starts_with?(absolute_path, cwd) do
          String.trim_leading(absolute_path, cwd <> "/")
        else
          absolute_path
        end

      _ ->
        absolute_path
    end
  end
end
