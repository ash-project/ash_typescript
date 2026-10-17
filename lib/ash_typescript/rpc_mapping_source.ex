# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.RpcMappingSource do
  @moduledoc """
  ash_typescript's `AshRpc.MappingSource`: client names come from the
  `typescript` resource DSL (`field_names`, `argument_names`), types'
  `typescript_field_names/0`, and the `typescript_rpc` domain DSL.

  The output formatter and `not_found_error?` are read while the manifest compiles;
  `AshTypescript.Manifest` tracks them with `Application.compile_env/3`.
  """

  @behaviour AshRpc.MappingSource

  alias AshTypescript.Helpers
  alias AshTypescript.Rpc.RpcAction

  @impl true
  def output_formatter,
    do: Application.get_env(:ash_typescript, :output_field_formatter, :camel_case)

  @impl true
  def exposed_resource?(module) when is_atom(module) do
    Code.ensure_loaded?(module) and Ash.Resource.Info.resource?(module) and
      AshTypescript.Resource in Spark.extensions(module)
  end

  @impl true
  def field_names(module),
    do: module |> AshTypescript.Resource.Info.typescript_field_names!() |> Map.new()

  @impl true
  def argument_names(module, action) do
    module
    |> AshTypescript.Resource.Info.typescript_argument_names!()
    |> Enum.find_value(%{}, fn
      {^action, mappings} -> Map.new(mappings)
      _ -> nil
    end)
  end

  @impl true
  def type_field_names(module) do
    if Helpers.has_typescript_field_names?(module), do: Helpers.typescript_field_names(module)
  end

  @impl true
  def entrypoint(
        %Ash.Info.Manifest.Entrypoint{
          config: %{ash_typescript: %{rpc_action: %RpcAction{} = rpc, domain: domain}}
        } = e
      ) do
    %AshRpc.Entrypoint{
      name: to_string(rpc.name),
      domain: domain,
      resource: e.resource,
      action: rpc.action,
      read_action: rpc.read_action,
      get?: rpc.get? || false,
      get_by: rpc.get_by || [],
      identities: rpc.identities || [:_primary_key],
      not_found_error?: resolve_not_found_error?(rpc.not_found_error?),
      enable_filter?: rpc.enable_filter? != false,
      enable_sort?: rpc.enable_sort? != false,
      load_restrictions: load_restrictions(rpc),
      exposed_metadata_fields: AshRpc.Introspection.get_exposed_metadata_fields(rpc, e.action),
      metadata_field_names: Map.new(rpc.metadata_field_names || [])
    }
  end

  def entrypoint(_entrypoint), do: nil

  @doc "Off-wire entrypoint for a typed query (stored in custom.ash_typescript)."
  def typed_query_entrypoint(
        %Ash.Info.Manifest.Entrypoint{
          config: %{ash_typescript: %{typed_query: tq, domain: domain}}
        } = e
      ) do
    %AshRpc.Entrypoint{
      name: to_string(tq.name),
      domain: domain,
      resource: e.resource,
      action: tq.action,
      not_found_error?: resolve_not_found_error?(nil),
      preset_fields: tq.fields
    }
  end

  def typed_query_entrypoint(_entrypoint), do: nil

  defp resolve_not_found_error?(nil), do: AshTypescript.Rpc.not_found_error?()

  defp resolve_not_found_error?(value), do: value

  defp load_restrictions(%RpcAction{allowed_loads: allowed}) when not is_nil(allowed),
    do: {:allow, allowed}

  defp load_restrictions(%RpcAction{denied_loads: denied}) when not is_nil(denied),
    do: {:deny, denied}

  defp load_restrictions(_rpc), do: :none
end
