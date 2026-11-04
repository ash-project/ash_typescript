# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Codegen.NameBuildersTest do
  # The generated-name builders that take the output formatter: under the
  # configured formatter they equal their formatter-free forms (what codegen
  # emits), and with another formatter they follow it.
  use ExUnit.Case, async: true

  alias AshTypescript.Codegen.{SchemaCore, ValibotSchemaGenerator, ZodSchemaGenerator}
  alias AshTypescript.FieldFormatter
  alias AshTypescript.Manifest.Custom
  alias AshTypescript.Rpc.Codegen.FunctionNames
  alias AshTypescript.Test.CodegenTestHelper
  alias AshTypescript.TypedController.Codegen, as: RouteCodegen

  setup_all do
    manifest = AshTypescript.manifest()

    rpc_names =
      for entrypoint <- manifest.entrypoints,
          rpc_action = Custom.rpc_action(entrypoint),
          rpc_action != nil,
          do: rpc_action.name

    typed_queries =
      for entrypoint <- manifest.entrypoints,
          typed_query = Custom.typed_query(entrypoint),
          typed_query != nil,
          do: typed_query

    %{
      formatter: AshTypescript.output_field_formatter(),
      rpc_names: rpc_names,
      typed_queries: typed_queries
    }
  end

  describe "RPC function names" do
    test "each FunctionNames builder equals its old form for every RPC action of the test app",
         %{formatter: formatter, rpc_names: rpc_names} do
      assert rpc_names != []

      for name <- rpc_names,
          builder <- [:execution, :validation, :channel, :validation_channel] do
        assert apply(FunctionNames, builder, [name, formatter]) ==
                 apply(FunctionNames, builder, [name])
      end
    end

    test "the formatter-taking forms follow the given formatter" do
      assert FunctionNames.execution(:list_todos, :snake_case) == "list_todos"
      assert FunctionNames.execution(:list_todos, :camel_case) == "listTodos"
      assert FunctionNames.validation(:list_todos, :pascal_case) == "ValidateListTodos"
      assert FunctionNames.channel(:list_todos, :snake_case) == "list_todos_channel"

      assert FunctionNames.validation_channel(:list_todos, :camel_case) ==
               "validateListTodosChannel"
    end
  end

  describe "typed query names" do
    test "typed query builders equal codegen's names", %{typed_queries: typed_queries} do
      assert typed_queries != []
      {:ok, content} = CodegenTestHelper.generate_all_content()

      for typed_query <- typed_queries do
        const = FunctionNames.typed_query_const(typed_query)
        type = FunctionNames.typed_query_result_type(typed_query)

        assert content =~ "export const #{const} ", "missing const #{const}"
        assert content =~ "export type #{type} ", "missing type #{type}"
      end
    end

    test "a typed query option wins" do
      typed_query = %AshTypescript.Rpc.TypedQuery{
        name: :list_things,
        ts_fields_const_name: "myFields",
        ts_result_type_name: "MyResult"
      }

      assert FunctionNames.typed_query_const(typed_query) == "myFields"
      assert FunctionNames.typed_query_const(typed_query, :snake_case) == "myFields"
      assert FunctionNames.typed_query_result_type(typed_query) == "MyResult"
    end

    test "without options, the names come from the typed query's name" do
      typed_query = %AshTypescript.Rpc.TypedQuery{name: :list_things}

      assert FunctionNames.typed_query_const(typed_query, :snake_case) == "list_things"
      assert FunctionNames.typed_query_const(typed_query, :camel_case) == "listThings"
      assert FunctionNames.typed_query_result_type(typed_query) == "ListThingsResult"
    end
  end

  describe "action schema names" do
    test "action_schema_name/3 equals action_schema_name/2 under the configured formatter",
         %{formatter: formatter, rpc_names: rpc_names} do
      for schema_formatter <- [ZodSchemaGenerator, ValibotSchemaGenerator], name <- rpc_names do
        assert SchemaCore.action_schema_name(schema_formatter, name, formatter) ==
                 SchemaCore.action_schema_name(schema_formatter, name)
      end
    end

    test "action_schema_name/3 follows the given formatter" do
      suffix = ZodSchemaGenerator.schema_suffix()

      assert SchemaCore.action_schema_name(ZodSchemaGenerator, :list_todos, :snake_case) ==
               FieldFormatter.format_field_name("list_todos#{suffix}", :snake_case)
    end
  end

  describe "route names" do
    setup do
      routes = AshTypescript.manifest() |> Custom.routes()
      %{routes: routes}
    end

    test "route builders equal their old names for every route of the test app",
         %{routes: routes} do
      assert routes != []

      for route <- routes, formatter <- [:camel_case, :snake_case, :pascal_case] do
        format = &FieldFormatter.format_field_name(&1, formatter)

        assert RouteCodegen.route_function_name(route, nil, :action, formatter) ==
                 format.(route.name)

        assert RouteCodegen.route_function_name(route.name, nil, :path, formatter) ==
                 format.(:"#{route.name}_path")

        assert RouteCodegen.route_zod_schema_name(route, nil, formatter) ==
                 (route.zod_schema_name ||
                    format.(:"#{route.name}#{AshTypescript.Rpc.zod_schema_suffix()}"))

        assert RouteCodegen.route_valibot_schema_name(route, nil, formatter) ==
                 (route.valibot_schema_name ||
                    format.(:"#{route.name}#{AshTypescript.Rpc.valibot_schema_suffix()}"))
      end
    end

    test "a scope prefix comes first" do
      assert RouteCodegen.route_function_name(:login, "admin", :action, :camel_case) ==
               "adminLogin"

      assert RouteCodegen.route_function_name(:login, "admin", :path, :snake_case) ==
               "admin_login_path"

      route = %AshTypescript.Manifest.Route{name: :login}

      assert RouteCodegen.route_zod_schema_name(route, "admin", :camel_case) ==
               FieldFormatter.format_field_name(
                 :"admin_login#{AshTypescript.Rpc.zod_schema_suffix()}",
                 :camel_case
               )
    end

    test "the configured-formatter forms equal the formatter-taking ones", %{routes: routes} do
      formatter = AshTypescript.output_field_formatter()

      for route <- routes do
        assert RouteCodegen.route_zod_schema_name(route, nil) ==
                 RouteCodegen.route_zod_schema_name(route, nil, formatter)

        assert RouteCodegen.route_valibot_schema_name(route, "scope") ==
                 RouteCodegen.route_valibot_schema_name(route, "scope", formatter)
      end
    end

    test "a schema-name override on the manifest route wins", %{routes: routes} do
      create_task =
        Enum.find(
          routes,
          &(&1.source_module == AshTypescript.Test.Session and &1.name == :create_task)
        )

      for formatter <- [:camel_case, :snake_case] do
        assert RouteCodegen.route_zod_schema_name(create_task, nil, formatter) ==
                 "createTaskRouteZodSchema"

        assert RouteCodegen.route_valibot_schema_name(create_task, "scope", formatter) ==
                 "createTaskRouteValibotSchema"
      end
    end
  end
end
