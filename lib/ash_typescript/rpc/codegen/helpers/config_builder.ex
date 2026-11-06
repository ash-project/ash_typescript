# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.Codegen.Helpers.ConfigBuilder do
  @moduledoc """
  Builds TypeScript configuration field definitions for RPC functions.

  Configuration fields define the parameters that can be passed to RPC functions,
  including tenant, primary key, input, pagination, filters, and metadata fields.
  """

  import AshTypescript.Helpers

  alias AshTypescript.Codegen.{ClientNames, TypeMapper}
  alias AshTypescript.Rpc.Codegen.FunctionNames
  alias AshTypescript.Rpc.Codegen.Helpers.{ActionIntrospection, EntrypointOptions}

  @doc """
  Gets the action context - a map of values indicating what features the action supports.

  The rpc_action's options (`get?`, `get_by`, `enable_filter?`, `enable_sort?`,
  `identities`) are read from its wire entrypoint through `EntrypointOptions`.

  ## Parameters

    * `resource` - The Ash resource
    * `action` - The Ash action
    * `rpc_action` - The RPC action configuration

  ## Returns

  A map with the following keys:
  - `:requires_tenant` - Whether the action requires a tenant parameter
  - `:identities` - List of identity atoms for record lookup (update/destroy actions)
  - `:supports_pagination` - Whether the action supports pagination (list reads)
  - `:supports_filtering` - Whether the action supports filtering (list reads)
  - `:supports_sorting` - Whether the action supports sorting (list reads)
  - `:action_input_type` - Whether the input is :none, :required, or :optional
  - `:is_get_action` - Whether this is a get action (returns single or null)

  ## Examples

      iex> get_action_context(MyResource, read_action, rpc_action)
      %{
        requires_tenant: true,
        identities: [],
        supports_pagination: true,
        supports_filtering: true,
        supports_sorting: true,
        action_input_type: :required,
        is_get_action: false
      }
  """
  def get_action_context(resource, action, rpc_action) do
    entrypoint = EntrypointOptions.entrypoint!(rpc_action)
    is_get_action = EntrypointOptions.get?(entrypoint, action)
    list_read? = action.type == :read and not is_get_action

    identities =
      if action.type in [:update, :destroy] do
        EntrypointOptions.identities(entrypoint)
      else
        []
      end

    %{
      requires_tenant: AshTypescript.Rpc.requires_tenant_parameter?(resource),
      identities: identities,
      supports_pagination: list_read? and ActionIntrospection.action_supports_pagination?(action),
      supports_filtering: filtering?(action, entrypoint),
      supports_sorting: list_read? and EntrypointOptions.sort_enabled?(entrypoint),
      action_input_type: ActionIntrospection.action_input_type(action),
      is_get_action: is_get_action
    }
  end

  @doc """
  Whether an action's config takes a `filter` (typed by the resource's
  `<Resource>FilterInput`): a list read with filtering enabled. The one
  predicate for the RPC file, its exports and the JSON manifest.
  """
  @spec filtering?(map(), AshRpc.Entrypoint.t()) :: boolean()
  def filtering?(action, %AshRpc.Entrypoint{} = entrypoint) do
    action.type == :read and not EntrypointOptions.get?(entrypoint, action) and
      EntrypointOptions.filter_enabled?(entrypoint)
  end

  @doc """
  Whether an action takes an optional `page` (and so gets a `<Pascal>Config`
  type): a list read with fields that supports pagination without requiring it.
  The one predicate for the RPC file, its exports and the JSON manifest.
  """
  @spec optional_pagination?(map(), AshRpc.Entrypoint.t(), boolean()) :: boolean()
  def optional_pagination?(action, %AshRpc.Entrypoint{} = entrypoint, has_fields) do
    action.type == :read and not EntrypointOptions.get?(entrypoint, action) and
      ActionIntrospection.action_supports_pagination?(action) and
      not ActionIntrospection.action_requires_pagination?(action) and has_fields
  end

  @doc """
  Generates pagination configuration fields for the TypeScript config type.

  Returns a list of TypeScript field strings that define the `page` parameter
  for pagination. The structure varies based on what pagination types are supported.

  ## Parameters

    * `action` - The Ash action

  ## Returns

  A list of TypeScript field definition strings, or an empty list if pagination is not supported.

  ## Examples

      # Offset pagination only
      ["  page?: {", "    limit?: number;", "    offset?: number;", "  };"]

      # Keyset pagination only
      ["  page?: {", "    limit?: number;", "    after?: string;", "    before?: string;", "  };"]

      # Mixed pagination (both offset and keyset)
      ["  page?: (", "    {", "      limit?: number;", "      offset?: number;", "    } | {", ...]
  """
  def generate_pagination_config_fields(action) do
    supports_offset = ActionIntrospection.action_supports_offset_pagination?(action)
    supports_keyset = ActionIntrospection.action_supports_keyset_pagination?(action)
    supports_countable = ActionIntrospection.action_supports_countable?(action)
    is_required = ActionIntrospection.action_requires_pagination?(action)
    has_default_limit = ActionIntrospection.action_has_default_limit?(action)

    if supports_offset or supports_keyset do
      optional_mark = if is_required, do: "", else: "?"
      limit_required = if is_required and not has_default_limit, do: "", else: "?"

      cond do
        supports_offset and supports_keyset ->
          generate_mixed_pagination_config_fields(
            limit_required,
            supports_countable,
            optional_mark
          )

        supports_offset ->
          generate_offset_pagination_config_fields(
            limit_required,
            supports_countable,
            optional_mark
          )

        supports_keyset ->
          generate_keyset_pagination_config_fields(
            limit_required,
            supports_countable,
            optional_mark
          )
      end
    else
      []
    end
  end

  @doc """
  Builds the identity configuration field for the TypeScript config type.

  Generates a union type for all supported identities (primary key and/or named identities).

  ## Parameters

    * `resource` - The Ash resource
    * `identities` - List of identity atoms (e.g., `[:_primary_key, :email]`)
    * `opts` - Options keyword list:
      - `:validation_function?` - If true, each field type becomes `Type | string` to accept
        either the typed value or a string representation (for validation functions)

  ## Returns

  A list containing one TypeScript field definition string for the identity.

  ## Examples

      # Single primary key (non-composite)
      ["  identity: UUID;"]

      # Single primary key for validation function
      ["  identity: UUID | string;"]

      # Primary key and email identity (identity uses email field)
      ["  identity: UUID | { email: string };"]

      # Composite primary key
      ["  identity: { id: UUID; tenantId: string };"]

      # Composite primary key for validation function
      ["  identity: { id: UUID | string; tenantId: string };"]
  """
  def build_identity_config_field(resource, identities, opts) do
    resource_lookup = AshTypescript.resource_lookup()

    build_identity_config_field(resource, identities, opts, resource_lookup)
  end

  @doc """
  Builds the identity configuration field with pre-computed resource_lookup.
  """
  def build_identity_config_field(resource, identities, opts, resource_lookup) do
    validation_function? = Keyword.get(opts, :validation_function?, false)

    identity_types =
      Enum.map(identities, fn identity ->
        build_single_identity_type(resource, identity, validation_function?, resource_lookup)
      end)

    formatted_identity = formatted_identity_field()
    union_type = Enum.join(identity_types, " | ")

    ["  #{formatted_identity}: #{union_type};"]
  end

  defp build_single_identity_type(resource, :_primary_key, validation_function?, resource_lookup) do
    primary_key_attrs = Ash.Info.Manifest.primary_key(resource_lookup, resource)

    if Enum.count(primary_key_attrs) == 1 do
      attr_name = Enum.at(primary_key_attrs, 0)
      attr = Ash.Info.Manifest.get_field(resource_lookup, resource, attr_name)
      base_type = TypeMapper.map_plain_type(attr.type, :input)

      if validation_function? do
        maybe_add_string_union(base_type)
      else
        base_type
      end
    else
      field_types =
        Enum.map_join(primary_key_attrs, "; ", fn attr_name ->
          attr = Ash.Info.Manifest.get_field(resource_lookup, resource, attr_name)
          formatted_attr_name = get_formatted_field_name(resource, attr.name)
          base_type = TypeMapper.map_plain_type(attr.type, :input)

          type =
            if validation_function? do
              maybe_add_string_union(base_type)
            else
              base_type
            end

          "#{formatted_attr_name}: #{type}"
        end)

      "{ #{field_types} }"
    end
  end

  # `VerifyIdentities` has checked that the resource declares the identity.
  defp build_single_identity_type(resource, identity_name, validation_function?, resource_lookup) do
    identity = Ash.Info.Manifest.get_identity(resource_lookup, resource, identity_name)

    # Use identity field names directly (e.g., { email: string } not { uniqueEmail: string })
    field_types =
      Enum.map_join(identity.keys, "; ", fn key ->
        formatted_key = get_formatted_field_name(resource, key)
        attr = Ash.Info.Manifest.get_field(resource_lookup, resource, key)
        base_type = TypeMapper.map_plain_type(attr.type, :input)

        type =
          if validation_function? do
            maybe_add_string_union(base_type)
          else
            base_type
          end

        "#{formatted_key}: #{type}"
      end)

    "{ #{field_types} }"
  end

  defp maybe_add_string_union("string"), do: "string"
  defp maybe_add_string_union(type), do: "#{type} | string"

  defp get_formatted_field_name(resource, field_name),
    do: ClientNames.resource_field(resource, field_name)

  @doc """
  Builds common configuration fields shared across all RPC functions.

  This includes tenant, primary key, input, and hook context fields.

  ## Parameters

    * `resource` - The Ash resource
    * `_action` - The Ash action (currently unused but kept for consistency)
    * `context` - The action context from `get_action_context/3`
    * `opts` - Options keyword list:
      - `:rpc_action_name` - The snake_case name of the RPC action
      - `:validation_function?` - If true, identity types accept `Type | string`
      - `:is_validation` - If true, this is for a validation function
      - `:is_channel` - If true, this is for a channel function

  ## Returns

  A list of TypeScript field definition strings.

  ## Examples

      ["  tenant: string;", "  input: CreateTodoInput;", "  hookCtx?: ActionHookContext;"]
  """
  def build_common_config_fields(resource, _action, context, opts) do
    input_type = FunctionNames.input_type(opts[:rpc_action_name] || "action")
    validation_function? = Keyword.get(opts, :validation_function?, false)
    is_validation = Keyword.get(opts, :is_validation, false)
    is_channel = Keyword.get(opts, :is_channel, false)

    config_fields = []

    config_fields =
      if context.requires_tenant do
        config_fields ++ ["  #{formatted_tenant_field()}: string;"]
      else
        config_fields ++ ["  #{formatted_tenant_field()}?: string;"]
      end

    config_fields =
      if context.identities != [] do
        config_fields ++
          build_identity_config_field(resource, context.identities,
            validation_function?: validation_function?
          )
      else
        config_fields
      end

    config_fields =
      case context.action_input_type do
        :required ->
          config_fields ++ ["  #{formatted_input_field()}: #{input_type};"]

        :optional ->
          config_fields ++ ["  #{formatted_input_field()}?: #{input_type};"]

        :none ->
          config_fields
      end

    config_fields =
      cond do
        # Channel validation hooks
        is_channel and is_validation and AshTypescript.Rpc.rpc_validation_channel_hooks_enabled?() ->
          config_fields ++ [hook_ctx_config_field("ValidationChannelHookContext")]

        # Channel action hooks
        is_channel and not is_validation and AshTypescript.Rpc.rpc_action_channel_hooks_enabled?() ->
          config_fields ++ [hook_ctx_config_field("ActionChannelHookContext")]

        # HTTP validation hooks
        not is_channel and is_validation and AshTypescript.Rpc.rpc_validation_hooks_enabled?() ->
          config_fields ++ [hook_ctx_config_field("ValidationHookContext")]

        # HTTP action hooks
        not is_channel and not is_validation and AshTypescript.Rpc.rpc_action_hooks_enabled?() ->
          config_fields ++ [hook_ctx_config_field("ActionHookContext")]

        true ->
          config_fields
      end

    config_fields
  end

  defp hook_ctx_config_field(hook_context_type) do
    "  #{formatted_hook_ctx_field()}?: #{hook_context_type};"
  end

  @doc """
  Builds the getBy configuration field for the TypeScript config type.

  This is used for `get_by` RPC actions where records are looked up by specific fields.

  ## Parameters

    * `resource` - The Ash resource
    * `rpc_action` - The RPC action configuration

  ## Returns

  A list of TypeScript field definition strings, or an empty list if no get_by fields.

  ## Examples

      # Single get_by field
      ["  getBy: {", "    email: string;", "  };"]

      # Multiple get_by fields
      ["  getBy: {", "    userId: UUID;", "    status: Status;", "  };"]
  """
  def build_get_by_config_field(resource, rpc_action) do
    resource_lookup = AshTypescript.resource_lookup()

    build_get_by_config_field(resource, rpc_action, resource_lookup)
  end

  @doc """
  Builds the getBy configuration field with pre-computed resource_lookup.
  """
  def build_get_by_config_field(resource, rpc_action, resource_lookup) do
    get_by_fields = rpc_action |> EntrypointOptions.entrypoint!() |> EntrypointOptions.get_by()

    if get_by_fields == [] do
      []
    else
      formatted_get_by = formatted_get_by_field()

      field_lines =
        Enum.map(get_by_fields, fn field_name ->
          attr = Ash.Info.Manifest.get_field(resource_lookup, resource, field_name)

          formatted_field_name =
            ClientNames.resource_field(Map.fetch!(resource_lookup, resource), field_name)

          "    #{formatted_field_name}: #{TypeMapper.map_plain_type(attr.type, :input)};"
        end)

      ["  #{formatted_get_by}: {"] ++ field_lines ++ ["  };"]
    end
  end

  defp generate_offset_pagination_config_fields(limit_required, supports_countable, optional_mark) do
    fields = [
      "    #{formatted_limit_field()}#{limit_required}: number;",
      "    #{formatted_offset_field()}?: number;",
      "    #{formatted_after_field()}?: never;",
      "    #{formatted_before_field()}?: never;"
    ]

    fields =
      if supports_countable do
        fields ++ ["    #{formatted_count_field()}?: boolean;"]
      else
        fields
      end

    [
      "  #{formatted_page_field()}#{optional_mark}: {"
    ] ++
      fields ++
      [
        "  };"
      ]
  end

  defp generate_keyset_pagination_config_fields(limit_required, supports_countable, optional_mark) do
    count_type = if supports_countable, do: "boolean", else: "never"

    fields = [
      "    #{formatted_limit_field()}#{limit_required}: number;",
      "    #{formatted_after_field()}?: string;",
      "    #{formatted_before_field()}?: string;",
      "    #{formatted_offset_field()}?: never;",
      "    #{formatted_count_field()}?: #{count_type};"
    ]

    [
      "  #{formatted_page_field()}#{optional_mark}: {"
    ] ++
      fields ++
      [
        "  };"
      ]
  end

  defp generate_mixed_pagination_config_fields(limit_required, supports_countable, optional_mark) do
    offset_fields = [
      "      #{formatted_limit_field()}#{limit_required}: number;",
      "      #{formatted_offset_field()}?: number;"
    ]

    offset_fields =
      if supports_countable do
        offset_fields ++ ["      #{formatted_count_field()}?: boolean;"]
      else
        offset_fields
      end

    keyset_fields = [
      "      #{formatted_limit_field()}#{limit_required}: number;",
      "      #{formatted_after_field()}?: string;",
      "      #{formatted_before_field()}?: string;"
    ]

    [
      "  #{formatted_page_field()}#{optional_mark}: ("
    ] ++
      [
        "    {"
      ] ++
      offset_fields ++
      [
        "    } | {"
      ] ++
      keyset_fields ++
      [
        "    }"
      ] ++
      [
        "  );"
      ]
  end
end
