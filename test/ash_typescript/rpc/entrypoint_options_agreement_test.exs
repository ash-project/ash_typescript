# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.EntrypointOptionsAgreementTest do
  @moduledoc """
  The per-rpc_action options codegen uses agree with the wire entrypoint the
  runtime uses (`%AshRpc.Entrypoint{}`), read through
  `AshTypescript.Rpc.Codegen.Helpers.EntrypointOptions`, for every rpc_action of
  the test manifest. Each option is checked against the generated output (the
  JSON manifest and the RPC file) or the codegen value that shapes it.
  """
  use ExUnit.Case, async: false

  alias AshTypescript.Helpers
  alias AshTypescript.Rpc.Codegen.FunctionNames
  alias AshTypescript.Rpc.Codegen.Helpers.ConfigBuilder
  alias AshTypescript.Rpc.Codegen.Helpers.EntrypointOptions
  alias AshTypescript.Rpc.Codegen.JsonManifestGenerator
  alias AshTypescript.Rpc.Codegen.RpcConfigCollector
  alias AshTypescript.Rpc.Codegen.TypeGenerators.MetadataTypes
  alias AshTypescript.Test.CodegenTestHelper

  @moduletag :ash_typescript

  setup_all do
    {:ok, files} = CodegenTestHelper.generate_files()

    json_actions =
      :ash_typescript
      |> JsonManifestGenerator.generate_json_manifest()
      |> Jason.decode!()
      |> Map.fetch!("actions")
      |> Map.new(&{&1["functionName"], &1})

    rpc_actions = RpcConfigCollector.get_rpc_resources_and_actions(AshTypescript.entrypoints())

    {:ok, rpc: CodegenTestHelper.rpc_content(files), json: json_actions, rpc_actions: rpc_actions}
  end

  test "get? agrees with the codegen copies", ctx do
    for {resource, action, rpc_action} <- ctx.rpc_actions do
      e = EntrypointOptions.entrypoint!(rpc_action)
      get? = EntrypointOptions.get?(e, action)
      label = inspect(rpc_action.name)

      assert json_entry(ctx, rpc_action)["get"] == get?, label

      assert ConfigBuilder.get_action_context(resource, action, rpc_action).is_get_action ==
               get?,
             label

      if action.type == :read do
        block = infer_result_block(ctx.rpc, rpc_action)
        # An array result, not the `ReadonlyArray<…>` of a metadata parameter
        assert block =~ ~r/(?<!Readonly)Array</ == not get?, "#{label}: #{block}"
      end
    end
  end

  test "filter and sort agree", ctx do
    for {resource, action, rpc_action} <- ctx.rpc_actions do
      e = EntrypointOptions.entrypoint!(rpc_action)
      entry = json_entry(ctx, rpc_action)
      label = inspect(rpc_action.name)

      assert entry["enableFilter"] == EntrypointOptions.filter_enabled?(e), label
      assert entry["enableSort"] == EntrypointOptions.sort_enabled?(e), label

      list_read? = action.type == :read and not EntrypointOptions.get?(e, action)
      config = function_config(ctx.rpc, rpc_action)
      context = ConfigBuilder.get_action_context(resource, action, rpc_action)

      expect_filter = list_read? and EntrypointOptions.filter_enabled?(e)
      expect_sort = list_read? and EntrypointOptions.sort_enabled?(e)

      assert config =~ "\n  filter?:" == expect_filter, "#{label}: #{config}"
      assert config =~ "\n  sort?:" == expect_sort, "#{label}: #{config}"
      assert context.supports_filtering == expect_filter, label
      assert context.supports_sorting == expect_sort, label
    end
  end

  test "load restrictions agree", ctx do
    for {_resource, _action, rpc_action} <- ctx.rpc_actions do
      e = EntrypointOptions.entrypoint!(rpc_action)
      declared? = ctx.rpc =~ ~r/^type #{pascal(rpc_action)}Schema = /m

      assert declared? == (EntrypointOptions.load_restrictions(e) != :none),
             inspect(rpc_action.name)
    end
  end

  test "not_found_error? agrees", ctx do
    gets =
      for {_resource, %{type: :read} = action, rpc_action} <- ctx.rpc_actions,
          e = EntrypointOptions.entrypoint!(rpc_action),
          EntrypointOptions.get?(e, action),
          do: {rpc_action, e}

    assert Enum.any?(gets, fn {_, e} -> not EntrypointOptions.not_found_error?(e) end)

    for {rpc_action, e} <- gets do
      block = infer_result_block(ctx.rpc, rpc_action)

      assert String.ends_with?(block, "| null;") == not EntrypointOptions.not_found_error?(e),
             "#{inspect(rpc_action.name)}: #{block}"
    end
  end

  test "identities and metadata agree", ctx do
    for {resource, action, rpc_action} <- ctx.rpc_actions do
      e = EntrypointOptions.entrypoint!(rpc_action)
      label = inspect(rpc_action.name)
      identities = EntrypointOptions.identities(e)

      if action.type in [:update, :destroy] do
        assert ConfigBuilder.get_action_context(resource, action, rpc_action).identities ==
                 identities,
               label

        config = function_config(ctx.rpc, rpc_action)
        assert config =~ "\n  identity:" == (identities != []), "#{label}: #{config}"
      end

      assert EntrypointOptions.exposed_metadata_fields(e) ==
               MetadataTypes.exposed_metadata_fields(rpc_action),
             label

      assert EntrypointOptions.get_by(e) == (rpc_action.get_by || []), label
    end
  end

  test "default identities are ash_rpc's" do
    assert EntrypointOptions.default_identities() == [:_primary_key]
    assert EntrypointOptions.default_identities() == %AshRpc.Entrypoint{}.identities
  end

  defp json_entry(ctx, rpc_action),
    do: Map.fetch!(ctx.json, FunctionNames.execution(to_string(rpc_action.name)))

  defp pascal(rpc_action), do: Helpers.snake_to_pascal_case(to_string(rpc_action.name))

  # `export type Infer<Pascal>Result<...> = ...;` up to the blank line after it.
  defp infer_result_block(rpc, rpc_action) do
    [_, rest] = String.split(rpc, "export type Infer#{pascal(rpc_action)}Result", parts: 2)
    rest |> String.split("\n\n", parts: 2) |> hd() |> String.trim_trailing()
  end

  # The `config` parameter of the HTTP execution function, or the
  # `<Pascal>Config` type it takes when the action has optional pagination.
  defp function_config(rpc, rpc_action) do
    name = FunctionNames.execution(to_string(rpc_action.name))
    [_, rest] = Regex.split(~r/export async function #{name}[<(]/, rpc, parts: 2)
    config = rest |> String.split("): Promise<", parts: 2) |> hd()

    if config =~ "config: Config & {" do
      [_, type] = String.split(rpc, "export type #{pascal(rpc_action)}Config = {", parts: 2)
      type |> String.split("\n};", parts: 2) |> hd()
    else
      config
    end
  end
end
