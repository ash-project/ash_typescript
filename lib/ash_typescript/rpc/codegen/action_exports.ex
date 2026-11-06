# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.Codegen.ActionExports do
  @moduledoc """
  The names generated for one rpc_action: the functions and types the RPC file
  exports for it, its input schemas and the filter type its config takes.

  The one descriptor of an action's exported names, read by the RPC file's
  function shapes, the namespace re-export files and the JSON manifest. A slot
  is `nil` when the action gets no such export.
  """

  alias AshTypescript.Codegen.{SchemaCore, ValibotSchemaGenerator, ZodSchemaGenerator}
  alias AshTypescript.Rpc.Codegen.FunctionNames
  alias AshTypescript.Rpc.Codegen.Helpers.{ActionIntrospection, ConfigBuilder, EntrypointOptions}
  alias AshTypescript.Rpc.Codegen.TypeGenerators.MetadataTypes

  defstruct [
    :function,
    :validation,
    :channel,
    :validation_channel,
    :input,
    :zod_schema,
    :valibot_schema,
    :result,
    :fields,
    :infer_result,
    :config,
    :metadata,
    :filter_input
  ]

  @type t :: %__MODULE__{}

  @doc """
  The descriptor of `rpc_action` (on `action` of `resource`), under the current
  codegen settings (validation and channel functions, zod and valibot schemas).
  """
  @spec build(module(), map(), map()) :: t()
  def build(resource, action, rpc_action) do
    name = to_string(rpc_action.name)
    entrypoint = EntrypointOptions.entrypoint!(rpc_action)
    action = EntrypointOptions.mark_get(entrypoint, action)

    fields? = fields?(action)
    input? = SchemaCore.action_has_schema?(action)
    metadata? = MetadataTypes.metadata_enabled?(MetadataTypes.exposed_metadata_fields(rpc_action))
    validation? = AshTypescript.Rpc.generate_validation_functions?()
    channel? = AshTypescript.Rpc.generate_phx_channel_rpc_actions?()

    %__MODULE__{
      function: FunctionNames.execution(name),
      validation: if(validation?, do: FunctionNames.validation(name)),
      channel: if(channel?, do: FunctionNames.channel(name)),
      validation_channel:
        if(validation? and channel?, do: FunctionNames.validation_channel(name)),
      input: if(input?, do: FunctionNames.input_type(name)),
      zod_schema:
        if(input? and AshTypescript.Rpc.generate_zod_schemas?(),
          do: SchemaCore.action_schema_name(ZodSchemaGenerator, name)
        ),
      valibot_schema:
        if(input? and AshTypescript.Rpc.generate_valibot_schemas?(),
          do: SchemaCore.action_schema_name(ValibotSchemaGenerator, name)
        ),
      result: FunctionNames.result_type(name),
      fields: if(fields?, do: FunctionNames.fields_type(name)),
      infer_result:
        if(action.type != :destroy or metadata?, do: FunctionNames.infer_result_type(name)),
      config:
        if(ConfigBuilder.optional_pagination?(action, entrypoint, fields?),
          do: FunctionNames.config_type(name)
        ),
      metadata: if(metadata?, do: FunctionNames.metadata_type(name)),
      filter_input:
        if(ConfigBuilder.filtering?(action, entrypoint),
          do:
            resource
            |> AshTypescript.Codegen.Helpers.build_resource_type_name()
            |> FunctionNames.filter_input_type()
        )
    }
  end

  @doc """
  The names to re-export, each with where it comes from: `:value` and `:type`
  from the RPC file, `:zod_value` / `:valibot_value` from the schema files.
  The filter type is the resource's, so it is not among them.
  """
  @spec exports(t()) :: [{String.t(), :value | :type | :zod_value | :valibot_value}]
  def exports(%__MODULE__{} = exports) do
    [
      {exports.function, :value},
      {exports.validation, :value},
      {exports.channel, :value},
      {exports.validation_channel, :value},
      {exports.input, :type},
      {exports.zod_schema, :zod_value},
      {exports.valibot_schema, :valibot_value},
      {exports.result, :type},
      {exports.fields, :type},
      {exports.infer_result, :type},
      {exports.config, :type},
      {exports.metadata, :type}
    ]
    |> Enum.reject(fn {name, _kind} -> is_nil(name) end)
  end

  @doc """
  Whether the action selects fields (a `fields` config key and a `<Name>Fields`
  type): reads, creates and updates, and generic actions returning a resource,
  a typed map or a typed struct (or an array of one).
  """
  @spec fields?(map()) :: boolean()
  def fields?(%{type: :destroy}), do: false
  def fields?(%{type: type}) when type in [:read, :create, :update], do: true

  def fields?(%{type: :action} = action) do
    case ActionIntrospection.action_returns_field_selectable_type?(action) do
      {:ok, type, _} when type in [:unconstrained_map, :array_of_unconstrained_map] -> false
      {:ok, _, _} -> true
      _ -> false
    end
  end
end
