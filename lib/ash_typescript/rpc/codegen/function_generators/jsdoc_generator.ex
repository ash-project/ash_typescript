# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.Codegen.FunctionGenerators.JsdocGenerator do
  @moduledoc """
  Generates JSDoc comments for RPC functions.

  Provides IDE discoverability by adding documentation with metadata tags
  that describe the action type, resource, internal action name, and namespace.
  """

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
      /**
       * List all users
       *
       * @actionType :read
       * @resource MyApp.User
       * @internalActionName :list
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
      " * @actionType :#{action.type}"
    ]

    lines =
      if include_internals? do
        lines ++
          [" * @resource #{inspect(resource)}", " * @internalActionName :#{rpc_action.action}"]
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
      " * @actionType :#{action.type}"
    ]

    lines =
      if include_internals? do
        lines ++
          [" * @resource #{inspect(resource)}", " * @internalActionName :#{rpc_action.action}"]
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
        lines ++ [" * @resource #{inspect(resource)}"]
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
      # Convert snake_case atom to camelCase function name
      function_name = action_name |> Atom.to_string() |> Macro.camelize() |> decapitalize()
      " * @see #{function_name}"
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

  defp decapitalize(<<first::utf8, rest::binary>>), do: String.downcase(<<first::utf8>>) <> rest
  defp decapitalize(""), do: ""

  defp default_description(:read, resource_name), do: "Read #{resource_name} records"
  defp default_description(:create, resource_name), do: "Create a new #{resource_name}"
  defp default_description(:update, resource_name), do: "Update an existing #{resource_name}"
  defp default_description(:destroy, resource_name), do: "Delete a #{resource_name}"

  defp default_description(:action, resource_name),
    do: "Execute generic action on #{resource_name}"
end
