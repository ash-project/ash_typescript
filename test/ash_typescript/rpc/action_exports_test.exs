# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.ActionExportsTest do
  @moduledoc """
  The names the RPC file exports for each rpc_action agree with its namespace
  re-exports and its JSON manifest entry.
  """
  use ExUnit.Case, async: false

  alias AshTypescript.Codegen.{SchemaCore, ValibotSchemaGenerator, ZodSchemaGenerator}
  alias AshTypescript.Rpc.Codegen
  alias AshTypescript.Rpc.Codegen.{FunctionNames, JsonManifestGenerator, RpcConfigCollector}
  alias AshTypescript.Test.CodegenTestHelper

  setup_all do
    {:ok, files} = CodegenTestHelper.generate_files()
    rpc = CodegenTestHelper.rpc_content(files)

    actions =
      :ash_typescript
      |> RpcConfigCollector.get_rpc_resources_by_namespace()
      |> Enum.flat_map(fn {_namespace, actions} -> actions end)

    json =
      :ash_typescript
      |> JsonManifestGenerator.generate_json_manifest()
      |> Jason.decode!()
      |> Map.fetch!("actions")
      |> Map.new(&{&1["functionName"], &1})

    {:ok, rpc: rpc, actions: actions, json: json}
  end

  # Every name the RPC file can export for an rpc_action, kept when it does.
  defp rpc_exports(rpc, rpc_name) do
    types = [
      FunctionNames.input_type(rpc_name),
      FunctionNames.result_type(rpc_name),
      FunctionNames.fields_type(rpc_name),
      FunctionNames.infer_result_type(rpc_name),
      FunctionNames.config_type(rpc_name),
      FunctionNames.metadata_type(rpc_name)
    ]

    values = [
      FunctionNames.execution(rpc_name),
      FunctionNames.validation(rpc_name),
      FunctionNames.channel(rpc_name),
      FunctionNames.validation_channel(rpc_name)
    ]

    Enum.filter(types, &(rpc =~ ~r/^export type #{&1}\b/m)) ++
      Enum.filter(values, &(rpc =~ ~r/^export (async )?function #{&1}\b/m))
  end

  defp reexport(actions) do
    Codegen.generate_namespace_reexport_content(
      "ns",
      actions,
      Application.get_env(:ash_typescript, :output_file),
      nil,
      nil
    )
  end

  defp reexported_names(content) do
    ~r/export (?:type )?\{([^}]*)\} from/
    |> Regex.scan(content)
    |> Enum.flat_map(fn [_, names] -> String.split(names, ",", trim: true) end)
    |> Enum.map(&String.trim/1)
    |> MapSet.new()
  end

  defp action!(actions, name), do: Enum.find(actions, &(elem(&1, 2).name == name))

  # The generated execution function, up to the next export or doc comment.
  defp function_body(rpc, function_name) do
    [body] =
      Regex.run(~r/^export async function #{function_name}\b.*?(?=^\/\*\*|^export )/ms, rpc,
        capture: :first
      )

    body
  end

  describe "namespace re-exports" do
    test "a namespaced create or update action re-exports its Fields and InferResult",
         %{actions: actions} do
      for name <- [:create_user_settings, :update_user_settings] do
        names = actions |> action!(name) |> List.wrap() |> reexport() |> reexported_names()
        pascal = Macro.camelize(to_string(name))

        assert "#{pascal}Fields" in names
        assert "Infer#{pascal}Result" in names
      end
    end

    test "a generic action returning a resource re-exports its Fields and InferResult",
         %{actions: actions} do
      names =
        actions
        |> action!(:get_statistics_org_todo)
        |> List.wrap()
        |> reexport()
        |> reexported_names()

      assert "GetStatisticsOrgTodoFields" in names
      assert "InferGetStatisticsOrgTodoResult" in names
    end

    test "every name the RPC file exports for an action is re-exported",
         %{rpc: rpc, actions: actions} do
      for {_, _, rpc_action, _, _} = action <- actions do
        rpc_name = to_string(rpc_action.name)
        exported = rpc_exports(rpc, rpc_name)

        # The input schemas are re-exported from the schema files.
        schemas =
          for generator <- [ZodSchemaGenerator, ValibotSchemaGenerator],
              do: SchemaCore.action_schema_name(generator, rpc_name)

        names =
          [action] |> reexport() |> reexported_names() |> MapSet.difference(MapSet.new(schemas))

        assert MapSet.new(exported) == names,
               "#{rpc_action.name}: the RPC file exports #{inspect(exported)}, " <>
                 "the namespace file re-exports #{inspect(MapSet.to_list(names))}"
      end
    end
  end

  describe "JSON manifest types" do
    test "every type in an action's entry is exported for it, fields with inferResult",
         %{rpc: rpc, actions: actions, json: json} do
      for {_, _, rpc_action, _, _} <- actions do
        rpc_name = to_string(rpc_action.name)
        exported = rpc_exports(rpc, rpc_name)
        types = Map.fetch!(json, FunctionNames.execution(rpc_name))["types"]

        for {key, name} <- Map.delete(types, "filterInput") do
          assert name in exported, "#{rpc_name}: types.#{key} #{name} is not exported"
        end

        has_fields? = FunctionNames.fields_type(rpc_name) in exported
        assert Map.has_key?(types, "fields") == has_fields?, rpc_name
        assert Map.has_key?(types, "inferResult") == has_fields?, rpc_name

        for {key, name} <- [
              {"input", FunctionNames.input_type(rpc_name)},
              {"config", FunctionNames.config_type(rpc_name)}
            ] do
          assert Map.has_key?(types, key) == name in exported, "#{rpc_name}: types.#{key}"
        end
      end
    end

    test "filterInput is present exactly when the generated function takes a filter",
         %{rpc: rpc, actions: actions, json: json} do
      for {_, _, rpc_action, _, _} <- actions do
        function_name = FunctionNames.execution(to_string(rpc_action.name))
        types = Map.fetch!(json, function_name)["types"]
        takes_filter? = function_body(rpc, function_name) =~ "config.filter"

        assert Map.has_key?(types, "filterInput") == takes_filter?,
               "#{rpc_action.name}: filterInput #{inspect(types["filterInput"])}, " <>
                 "function takes a filter: #{takes_filter?}"
      end
    end

    test "a get action has no filterInput", %{json: json} do
      refute Map.has_key?(json["getTodo"]["types"], "filterInput")
      assert json["listTodos"]["types"]["filterInput"] == "TodoFilterInput"
    end
  end
end
