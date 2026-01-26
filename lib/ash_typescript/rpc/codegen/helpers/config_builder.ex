# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.Codegen.Helpers.ConfigBuilder do
  @moduledoc """
  Builds TypeScript configuration field definitions for RPC functions.

  Configuration fields define the parameters that can be passed to RPC functions,
  including tenant, primary key, input, pagination, filters, and metadata fields.
  """

  import AshTypescript.Codegen
  import AshTypescript.Helpers

  alias AshTypescript.Rpc.Codegen.Helpers.ActionIntrospection

  @doc """
  Gets the action context - a map of values indicating what features the action supports.

  Note: The action should be augmented with RPC settings (get?, get_by) before calling this.
  This is done in the codegen module via `augment_action_with_rpc_settings/3`.

  ## Parameters

    * `resource` - The Ash resource
    * `action` - The Ash action (possibly augmented with RPC settings)
    * `rpc_action` - The RPC action configuration

  ## Returns

  A map with the following keys:
  - `:requires_tenant` - Whether the action requires a tenant parameter
  - `:identities` - List of identity atoms for record lookup (update/destroy actions)
  - `:supports_pagination` - Whether the action supports pagination (list reads)
  - `:supports_filtering` - Whether the action supports filtering (list reads)
  - `:action_input_type` - Whether the input is :none, :required, or :optional
  - `:is_get_action` - Whether this is a get action (returns single or null)

  ## Examples

      iex> get_action_context(MyResource, read_action, rpc_action)
      %{
        requires_tenant: true,
        identities: [],
        supports_pagination: true,
        supports_filtering: true,
        action_input_type: :required,
        is_get_action: false
      }
  """
  def get_action_context(resource, action, rpc_action) do
    # Check both Ash's native get? and RPC's get?/get_by options
    ash_get? = action.type == :read and Map.get(action, :get?, false)
    rpc_get? = Map.get(rpc_action, :get?, false)
    rpc_get_by = (Map.get(rpc_action, :get_by) || []) != []

    is_get_action = ash_get? or rpc_get? or rpc_get_by

    # enable_filter? and enable_sort? default to true - when false, disables respective support
    enable_filter? = Map.get(rpc_action, :enable_filter?, true)
    enable_sort? = Map.get(rpc_action, :enable_sort?, true)

    identities =
      if action.type in [:update, :destroy] do
        Map.get(rpc_action, :identities, [:_primary_key])
      else
        []
      end

    %{
      requires_tenant: AshTypescript.Rpc.requires_tenant_parameter?(resource),
      identities: identities,
      supports_pagination:
        action.type == :read and not is_get_action and
          ActionIntrospection.action_supports_pagination?(action),
      supports_filtering: action.type == :read and not is_get_action and enable_filter?,
      supports_sorting: action.type == :read and not is_get_action and enable_sort?,
      action_input_type: ActionIntrospection.action_input_type(resource, action),
      is_get_action: is_get_action
    }
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
          generate_keyset_pagination_config_fields(limit_required, optional_mark)
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
    validation_function? = Keyword.get(opts, :validation_function?, false)

    identity_types =
      Enum.map(identities, fn identity ->
        build_single_identity_type(resource, identity, validation_function?)
      end)

    formatted_identity = format_output_field(:identity)
    union_type = Enum.join(identity_types, " | ")

    ["  #{formatted_identity}: #{union_type};"]
  end

  defp build_single_identity_type(resource, :_primary_key, validation_function?) do
    primary_key_attrs = Ash.Resource.Info.primary_key(resource)

    if Enum.count(primary_key_attrs) == 1 do
      attr_name = Enum.at(primary_key_attrs, 0)
      attr = Ash.Resource.Info.attribute(resource, attr_name)
      base_type = get_ts_type(attr)

      if validation_function? do
        maybe_add_string_union(base_type)
      else
        base_type
      end
    else
      # Composite primary key - always use object format
      field_types =
        Enum.map_join(primary_key_attrs, "; ", fn attr_name ->
          attr = Ash.Resource.Info.attribute(resource, attr_name)
          formatted_attr_name = get_formatted_field_name(resource, attr.name)
          base_type = get_ts_type(attr)

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

  defp build_single_identity_type(resource, identity_name, validation_function?) do
    identity = Ash.Resource.Info.identity(resource, identity_name)

    if identity do
      # Use identity field names directly (e.g., { email: string } not { uniqueEmail: string })
      field_types =
        Enum.map_join(identity.keys, "; ", fn key ->
          formatted_key = get_formatted_field_name(resource, key)
          attr = Ash.Resource.Info.attribute(resource, key)
          base_type = get_ts_type(attr)

          type =
            if validation_function? do
              maybe_add_string_union(base_type)
            else
              base_type
            end

          "#{formatted_key}: #{type}"
        end)

      "{ #{field_types} }"
    else
      "{ /* Identity #{identity_name} not found */ never }"
    end
  end

  # Adds "| string" to a type, unless the type is already "string"
  defp maybe_add_string_union("string"), do: "string"
  defp maybe_add_string_union(type), do: "#{type} | string"

  # Gets the formatted field name, applying field_names mappings and output formatter
  defp get_formatted_field_name(resource, field_name) do
    AshTypescript.FieldFormatter.format_field_for_client(
      field_name,
      resource,
      AshTypescript.Rpc.output_field_formatter()
    )
  end

  @doc """
  Builds common configuration fields shared across all RPC functions.

  This includes tenant, primary key, input, and hook context fields.

  ## Parameters

    * `resource` - The Ash resource
    * `_action` - The Ash action (currently unused but kept for consistency)
    * `context` - The action context from `get_action_context/2`
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
    rpc_action_name_pascal = snake_to_pascal_case(opts[:rpc_action_name] || "action")
    validation_function? = Keyword.get(opts, :validation_function?, false)
    is_validation = Keyword.get(opts, :is_validation, false)
    is_channel = Keyword.get(opts, :is_channel, false)

    config_fields = []

    config_fields =
      if context.requires_tenant do
        config_fields ++ ["  #{format_output_field(:tenant)}: string;"]
      else
        config_fields ++ ["  #{format_output_field(:tenant)}?: string;"]
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
          config_fields ++ ["  #{format_output_field(:input)}: #{rpc_action_name_pascal}Input;"]

        :optional ->
          config_fields ++ ["  #{format_output_field(:input)}?: #{rpc_action_name_pascal}Input;"]

        :none ->
          config_fields
      end

    # Add hookCtx field if hooks are enabled
    config_fields =
      cond do
        # Channel validation hooks
        is_channel and is_validation and AshTypescript.Rpc.rpc_validation_channel_hooks_enabled?() ->
          config_fields ++ ["  hookCtx?: ValidationChannelHookContext;"]

        # Channel action hooks
        is_channel and not is_validation and AshTypescript.Rpc.rpc_action_channel_hooks_enabled?() ->
          config_fields ++ ["  hookCtx?: ActionChannelHookContext;"]

        # HTTP validation hooks
        not is_channel and is_validation and AshTypescript.Rpc.rpc_validation_hooks_enabled?() ->
          config_fields ++ ["  hookCtx?: ValidationHookContext;"]

        # HTTP action hooks
        not is_channel and not is_validation and AshTypescript.Rpc.rpc_action_hooks_enabled?() ->
          config_fields ++ ["  hookCtx?: ActionHookContext;"]

        true ->
          config_fields
      end

    config_fields
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
    get_by_fields = Map.get(rpc_action, :get_by) || []

    if get_by_fields == [] do
      []
    else
      formatted_get_by = format_output_field(:get_by)

      field_lines =
        Enum.map(get_by_fields, fn field_name ->
          attr = Ash.Resource.Info.attribute(resource, field_name)
          formatted_field_name = format_output_field(field_name)
          "    #{formatted_field_name}: #{get_ts_type(attr)};"
        end)

      ["  #{formatted_get_by}: {"] ++ field_lines ++ ["  };"]
    end
  end

  # Private helper functions for pagination config fields

  defp generate_offset_pagination_config_fields(limit_required, supports_countable, optional_mark) do
    fields = [
      "    #{formatted_limit_field()}#{limit_required}: number;",
      "    #{formatted_offset_field()}?: number;",
      "    #{formatted_after_field()}?: never;",
      "    #{formatted_before_field()}?: never;"
    ]

    fields =
      if supports_countable do
        fields ++ ["    #{format_output_field(:count)}?: boolean;"]
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

  defp generate_keyset_pagination_config_fields(limit_required, optional_mark) do
    fields = [
      "    #{formatted_limit_field()}#{limit_required}: number;",
      "    #{formatted_after_field()}?: string;",
      "    #{formatted_before_field()}?: string;",
      "    #{formatted_offset_field()}?: never;",
      "    #{format_output_field(:count)}?: never;"
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
        offset_fields ++ ["      #{format_output_field(:count)}?: boolean;"]
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
