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
  Gets the action context - a map of booleans indicating what features the action supports.

  ## Returns

  A map with the following keys:
  - `:requires_tenant` - Whether the action requires a tenant parameter
  - `:requires_primary_key` - Whether the action requires a primary key (update/destroy)
  - `:supports_pagination` - Whether the action supports pagination (list reads)
  - `:supports_filtering` - Whether the action supports filtering (list reads)
  - `:action_input_type` - Whether the input is :none, :required, or :optional

  ## Examples

      iex> get_action_context(MyRes ource, read_action)
      %{
        requires_tenant: true,
        requires_primary_key: false,
        supports_pagination: true,
        supports_filtering: true,
        action_input_type: :required 
      }
  """
  def get_action_context(resource, action) do
    %{
      requires_tenant: AshTypescript.Rpc.requires_tenant_parameter?(resource),
      requires_primary_key: action.type in [:update, :destroy],
      supports_pagination:
        action.type == :read and not action.get? and
          ActionIntrospection.action_supports_pagination?(action),
      supports_filtering: action.type == :read and not action.get?,
      action_input_type: ActionIntrospection.action_input_type(resource, action)
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
  Builds the primary key configuration field for the TypeScript config type.

  ## Parameters

    * `resource` - The Ash resource
    * `opts` - Options keyword list:
      - `:simple_type` - If true, always use `string` type (for validation functions)

  ## Returns

  A list containing one TypeScript field definition string for the primary key.

  ## Examples

      # Single primary key attribute
      ["  primaryKey: string;"]

      # Composite primary key
      ["  primaryKey: {", "    id: number;", "    tenantId: string;", "  };"]
  """
  def build_primary_key_config_field(resource, opts) do
    primary_key_attrs = Ash.Resource.Info.primary_key(resource)
    simple_type = Keyword.get(opts, :simple_type, false)

    if simple_type do
      # For validation functions - always use string type
      formatted_primary_key = format_output_field(:primary_key)
      ["  #{formatted_primary_key}: string;"]
    else
      # For execution functions - use proper typing
      if Enum.count(primary_key_attrs) == 1 do
        attr_name = Enum.at(primary_key_attrs, 0)
        attr = Ash.Resource.Info.attribute(resource, attr_name)
        formatted_primary_key = format_output_field(:primary_key)
        ["  #{formatted_primary_key}: #{get_ts_type(attr)};"]
      else
        formatted_primary_key = format_output_field(:primary_key)

        [
          "  #{formatted_primary_key}: {"
        ] ++
          Enum.map(primary_key_attrs, fn attr_name ->
            attr = Ash.Resource.Info.attribute(resource, attr_name)
            formatted_attr_name = format_output_field(attr.name)
            "    #{formatted_attr_name}: #{get_ts_type(attr)};"
          end) ++
          [
            "  };"
          ]
      end
    end
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
      - `:simple_primary_key` - If true, use string type for primary key
      - `:is_validation` - If true, this is for a validation function
      - `:is_channel` - If true, this is for a channel function

  ## Returns

  A list of TypeScript field definition strings.

  ## Examples

      ["  tenant: string;", "  input: CreateTodoInput;", "  hookCtx?: ActionHookContext;"]
  """
  def build_common_config_fields(resource, _action, context, opts) do
    rpc_action_name_pascal = snake_to_pascal_case(opts[:rpc_action_name] || "action")
    simple_primary_key = Keyword.get(opts, :simple_primary_key, false)
    is_validation = Keyword.get(opts, :is_validation, false)
    is_channel = Keyword.get(opts, :is_channel, false)

    config_fields = []

    config_fields =
      if context.requires_tenant do
        config_fields ++ ["  #{format_output_field(:tenant)}: string;"]
      else
        config_fields
      end

    config_fields =
      if context.requires_primary_key do
        config_fields ++ build_primary_key_config_field(resource, simple_type: simple_primary_key)
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
