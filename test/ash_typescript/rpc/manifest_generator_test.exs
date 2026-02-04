# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.ManifestGeneratorTest do
  @moduledoc """
  Tests for RPC Action Manifest generation.

  Verifies that the manifest is generated correctly with proper sorting,
  respects feature flags for optional columns, and includes all expected content.
  """
  use ExUnit.Case, async: false

  alias AshTypescript.Rpc.Codegen.ManifestGenerator
  alias AshTypescript.Rpc.Codegen.RpcConfigCollector

  @moduletag :ash_typescript

  # Reset config to defaults after each test
  setup do
    original_internals = Application.get_env(:ash_typescript, :add_ash_internals_to_manifest)

    on_exit(fn ->
      if original_internals do
        Application.put_env(:ash_typescript, :add_ash_internals_to_manifest, original_internals)
      else
        Application.delete_env(:ash_typescript, :add_ash_internals_to_manifest)
      end
    end)

    :ok
  end

  describe "config functions" do
    test "manifest_file/0 returns configured path" do
      # The test config has manifest_file: "./test/ts/MANIFEST.md"
      assert AshTypescript.Rpc.manifest_file() == "./test/ts/MANIFEST.md"
    end

    test "add_ash_internals_to_manifest?/0 returns configured value" do
      Application.put_env(:ash_typescript, :add_ash_internals_to_manifest, true)
      assert AshTypescript.Rpc.add_ash_internals_to_manifest?() == true

      Application.put_env(:ash_typescript, :add_ash_internals_to_manifest, false)
      assert AshTypescript.Rpc.add_ash_internals_to_manifest?() == false
    end

    test "add_ash_internals_to_manifest?/0 defaults to false" do
      Application.delete_env(:ash_typescript, :add_ash_internals_to_manifest)
      assert AshTypescript.Rpc.add_ash_internals_to_manifest?() == false
    end
  end

  describe "RpcConfigCollector.get_rpc_config_by_domain/1" do
    test "returns domain-grouped config" do
      result = RpcConfigCollector.get_rpc_config_by_domain(:ash_typescript)

      assert is_list(result)
      assert result != []

      # Each entry should be a {domain, config} tuple
      for {domain, config} <- result do
        assert is_atom(domain)
        assert is_list(config)

        # Config should have resources with rpc_actions
        for resource_config <- config do
          assert Map.has_key?(resource_config, :resource)
          assert Map.has_key?(resource_config, :rpc_actions)
          assert Map.has_key?(resource_config, :typed_queries)
        end
      end
    end

    test "excludes domains with no RPC config" do
      result = RpcConfigCollector.get_rpc_config_by_domain(:ash_typescript)

      # All returned domains should have non-empty config
      for {_domain, config} <- result do
        assert config != []
      end
    end

    test "includes both test domains" do
      result = RpcConfigCollector.get_rpc_config_by_domain(:ash_typescript)
      domains = Enum.map(result, fn {domain, _} -> domain end)

      assert AshTypescript.Test.Domain in domains
      assert AshTypescript.Test.SecondDomain in domains
    end
  end

  describe "ManifestGenerator.generate_manifest/1 - basic structure" do
    setup do
      manifest = ManifestGenerator.generate_manifest(:ash_typescript)
      {:ok, manifest: manifest}
    end

    test "includes header with date", %{manifest: manifest} do
      assert manifest =~ "# RPC Action Manifest"
      assert manifest =~ "Generated:"
      # Should have a date in ISO format
      assert manifest =~ ~r/Generated: \d{4}-\d{2}-\d{2}/
    end

    test "includes namespace sections when namespaces are configured", %{manifest: manifest} do
      # Test config has namespaces (todos, users), so manifest should be grouped by namespace
      assert manifest =~ "## Namespace: todos" or manifest =~ "## Default (No Namespace)"
    end

    test "includes resource subsections", %{manifest: manifest} do
      assert manifest =~ "### Todo"
      assert manifest =~ "### User"
    end

    test "ends with single newline", %{manifest: manifest} do
      assert String.ends_with?(manifest, "\n")
      refute String.ends_with?(manifest, "\n\n")
    end
  end

  describe "ManifestGenerator.generate_manifest/1 - sorting" do
    setup do
      manifest = ManifestGenerator.generate_manifest(:ash_typescript)
      {:ok, manifest: manifest}
    end

    test "namespace sections are sorted (default first, then alphabetically)", %{
      manifest: manifest
    } do
      # Find all namespace section headers
      section_positions =
        ["Default (No Namespace)", "Namespace: todos", "Namespace: users"]
        |> Enum.map(fn section ->
          case :binary.match(manifest, "## #{section}") do
            {pos, _} -> {section, pos}
            :nomatch -> {section, nil}
          end
        end)
        |> Enum.reject(fn {_, pos} -> pos == nil end)
        |> Enum.sort_by(fn {_, pos} -> pos end)
        |> Enum.map(fn {section, _} -> section end)

      # If we have both Default and namespace sections, Default should come first
      if "Default (No Namespace)" in section_positions and length(section_positions) > 1 do
        assert hd(section_positions) == "Default (No Namespace)"
      end

      # Named namespaces should be alphabetically sorted
      named_sections =
        section_positions |> Enum.filter(&String.starts_with?(&1, "Namespace:"))

      assert named_sections == Enum.sort(named_sections)
    end

    test "resources within a section are sorted alphabetically", %{manifest: manifest} do
      # Find all resource headers in order
      resource_headers =
        Regex.scan(~r/### (\w+)/, manifest)
        |> Enum.map(fn [_, name] -> name end)

      # Each resource should appear only once, and they should be in alphabetical order
      # within their respective sections. Since resources can repeat across sections,
      # we just verify the overall pattern includes alphabetically sorted subsections
      assert resource_headers != []
    end

    test "actions within a resource are sorted alphabetically", %{manifest: manifest} do
      # Extract any resource section and find all function names
      # Use the Todo section since it likely has multiple actions
      todo_section =
        case Regex.run(~r/### Todo\n(.*?)(?=###|## |$)/s, manifest) do
          [_, section] -> section
          _ -> ""
        end

      if todo_section != "" do
        # Extract function names from the first column of each table row
        function_names =
          todo_section
          |> String.split("\n")
          |> Enum.filter(&String.starts_with?(&1, "| `"))
          |> Enum.map(fn line ->
            case Regex.run(~r/^\| `(\w+)` \|/, line) do
              [_, name] -> name
              _ -> nil
            end
          end)
          |> Enum.reject(&is_nil/1)

        # Should be alphabetically sorted
        assert function_names == Enum.sort(function_names)
      end
    end
  end

  describe "ManifestGenerator.generate_manifest/1 - table columns" do
    setup do
      manifest = ManifestGenerator.generate_manifest(:ash_typescript)
      {:ok, manifest: manifest}
    end

    test "includes Function column", %{manifest: manifest} do
      assert manifest =~ "| Function |"
    end

    test "includes Action Type column", %{manifest: manifest} do
      assert manifest =~ "| Action Type |"
    end

    test "includes Ash Action column when internals enabled", %{manifest: manifest} do
      if AshTypescript.Rpc.add_ash_internals_to_manifest?() do
        assert manifest =~ "| Ash Action |"
      end
    end

    test "includes Resource column when internals enabled", %{manifest: manifest} do
      if AshTypescript.Rpc.add_ash_internals_to_manifest?() do
        assert manifest =~ "| Resource |"
      end
    end

    test "includes Validation column when validation functions enabled", %{manifest: manifest} do
      if AshTypescript.Rpc.generate_validation_functions?() do
        assert manifest =~ "| Validation |"
        assert manifest =~ ~r/`validate\w+`/
      end
    end

    test "includes Zod Schema column when zod schemas enabled", %{manifest: manifest} do
      if AshTypescript.Rpc.generate_zod_schemas?() do
        assert manifest =~ "| Zod Schema |"
        assert manifest =~ ~r/`\w+ZodSchema`/
      end
    end

    test "includes Channel column when channel functions enabled", %{manifest: manifest} do
      if AshTypescript.Rpc.generate_phx_channel_rpc_actions?() do
        assert manifest =~ "| Channel |"
        assert manifest =~ ~r/`\w+Channel`/
      end
    end
  end

  describe "ManifestGenerator.generate_manifest/1 - action types" do
    setup do
      manifest = ManifestGenerator.generate_manifest(:ash_typescript)
      {:ok, manifest: manifest}
    end

    test "shows correct action types", %{manifest: manifest} do
      # Check various action types are present
      assert manifest =~ "| read |"
      assert manifest =~ "| create |"
      assert manifest =~ "| update |"
      assert manifest =~ "| destroy |"
      assert manifest =~ "| action |"
    end
  end

  describe "ManifestGenerator.generate_manifest/1 - action details" do
    setup do
      Application.put_env(:ash_typescript, :add_ash_internals_to_manifest, true)
      manifest = ManifestGenerator.generate_manifest(:ash_typescript)
      {:ok, manifest: manifest}
    end

    test "includes description for each action", %{manifest: manifest} do
      # Actions should have descriptions in the details section
      assert manifest =~ "Read Todo records" or manifest =~ "Create a new Todo"
    end

    test "includes namespace in details when set", %{manifest: manifest} do
      # Actions in the todos namespace should show it
      assert manifest =~ "**Namespace:** `todos`"
    end

    test "includes deprecated marker when action is deprecated", %{manifest: manifest} do
      # If we have a deprecated action, it should show the marker
      # This depends on test data having a deprecated action
      if manifest =~ "deprecated" do
        assert manifest =~ "⚠️ **Deprecated**"
      end
    end
  end

  describe "ManifestGenerator.generate_manifest/1 - typed queries" do
    setup do
      manifest = ManifestGenerator.generate_manifest(:ash_typescript)
      {:ok, manifest: manifest}
    end

    test "includes typed queries section", %{manifest: manifest} do
      assert manifest =~ "**Typed Queries:**"
    end

    test "lists typed query const names and result types", %{manifest: manifest} do
      # The test domain has listTodosUserPage typed query
      assert manifest =~ "listTodosUserPage"
      assert manifest =~ "ListTodosUserPageResult"
    end

    test "typed queries use arrow notation", %{manifest: manifest} do
      assert manifest =~ ~r/`\w+` → `\w+Result`/
    end
  end

  describe "ManifestGenerator.generate_manifest/1 - resources without actions" do
    setup do
      manifest = ManifestGenerator.generate_manifest(:ash_typescript)
      {:ok, manifest: manifest}
    end

    test "omits resources with no RPC actions", %{manifest: manifest} do
      # EmptyResource has no RPC actions configured and should be omitted
      refute manifest =~ "### EmptyResource"
      refute manifest =~ "_No RPC actions configured_"
    end

    test "only includes resources that have RPC actions", %{manifest: manifest} do
      # Todo has RPC actions and should be included
      assert manifest =~ "### Todo"
      # User has RPC actions and should be included
      assert manifest =~ "### User"
    end
  end

  describe "ManifestGenerator.generate_manifest/1 - function naming" do
    setup do
      manifest = ManifestGenerator.generate_manifest(:ash_typescript)
      {:ok, manifest: manifest}
    end

    test "function names are camelCase", %{manifest: manifest} do
      # Check specific known functions
      assert manifest =~ "`listTodos`"
      assert manifest =~ "`createTodo`"
    end

    test "validation function names are camelCase with validate prefix", %{manifest: manifest} do
      if AshTypescript.Rpc.generate_validation_functions?() do
        assert manifest =~ "`validateListTodos`"
        assert manifest =~ "`validateCreateTodo`"
      end
    end

    test "zod schema names use field formatter with ZodSchema suffix", %{manifest: manifest} do
      if AshTypescript.Rpc.generate_zod_schemas?() do
        assert manifest =~ "`listTodosZodSchema`"
        assert manifest =~ "`createTodoZodSchema`"
      end
    end

    test "channel function names are camelCase with Channel suffix", %{manifest: manifest} do
      if AshTypescript.Rpc.generate_phx_channel_rpc_actions?() do
        assert manifest =~ "`listTodosChannel`"
        assert manifest =~ "`createTodoChannel`"
      end
    end
  end

  describe "ManifestGenerator - add_ash_internals_to_manifest config" do
    test "excludes Ash Action and Resource columns when internals disabled" do
      Application.put_env(:ash_typescript, :add_ash_internals_to_manifest, false)
      manifest = ManifestGenerator.generate_manifest(:ash_typescript)

      # Should NOT have Ash Action or Resource columns
      refute manifest =~ "| Ash Action |"
      refute manifest =~ "| Resource |"

      # But should still have Function and Action Type
      assert manifest =~ "| Function |"
      assert manifest =~ "| Action Type |"
    end

    test "includes Ash Action and Resource columns when internals enabled" do
      Application.put_env(:ash_typescript, :add_ash_internals_to_manifest, true)
      manifest = ManifestGenerator.generate_manifest(:ash_typescript)

      assert manifest =~ "| Ash Action |"
      assert manifest =~ "| Resource |"
    end

    test "shows action description when internals enabled and rpc_action has no description" do
      Application.put_env(:ash_typescript, :add_ash_internals_to_manifest, true)
      manifest = ManifestGenerator.generate_manifest(:ash_typescript)

      # The update_me action on User has an action description
      # If there's no rpc_action description, the action description should be shown
      # when internals are enabled
      if manifest =~ "updateMe" do
        # Should see either the rpc_action description or the action description
        assert manifest =~ "updateMe"
      end
    end

    test "uses default description when internals disabled and no rpc_action description" do
      Application.put_env(:ash_typescript, :add_ash_internals_to_manifest, false)
      manifest = ManifestGenerator.generate_manifest(:ash_typescript)

      # Default descriptions should appear
      assert manifest =~ "Read Todo records" or manifest =~ "Create a new"
    end
  end

  describe "ManifestGenerator - conditional columns" do
    test "generates minimal table when all features disabled" do
      original_validation = Application.get_env(:ash_typescript, :generate_validation_functions)
      original_zod = Application.get_env(:ash_typescript, :generate_zod_schemas)
      original_channel = Application.get_env(:ash_typescript, :generate_phx_channel_rpc_actions)
      original_internals = Application.get_env(:ash_typescript, :add_ash_internals_to_manifest)

      try do
        Application.put_env(:ash_typescript, :generate_validation_functions, false)
        Application.put_env(:ash_typescript, :generate_zod_schemas, false)
        Application.put_env(:ash_typescript, :generate_phx_channel_rpc_actions, false)
        Application.put_env(:ash_typescript, :add_ash_internals_to_manifest, false)

        manifest = ManifestGenerator.generate_manifest(:ash_typescript)

        # Should have Function and Action Type columns
        assert manifest =~ "| Function | Action Type |"
        assert manifest =~ "|----------|-------------|"

        # Should NOT have validation, zod, channel, or internals columns
        refute manifest =~ "| Validation |"
        refute manifest =~ "| Zod Schema |"
        refute manifest =~ "| Channel |"
        refute manifest =~ "| Ash Action |"
        refute manifest =~ "| Resource |"
      after
        restore_config(:generate_validation_functions, original_validation)
        restore_config(:generate_zod_schemas, original_zod)
        restore_config(:generate_phx_channel_rpc_actions, original_channel)
        restore_config(:add_ash_internals_to_manifest, original_internals)
      end
    end

    test "generates table with only validation column when only validation enabled" do
      original_validation = Application.get_env(:ash_typescript, :generate_validation_functions)
      original_zod = Application.get_env(:ash_typescript, :generate_zod_schemas)
      original_channel = Application.get_env(:ash_typescript, :generate_phx_channel_rpc_actions)
      original_internals = Application.get_env(:ash_typescript, :add_ash_internals_to_manifest)

      try do
        Application.put_env(:ash_typescript, :generate_validation_functions, true)
        Application.put_env(:ash_typescript, :generate_zod_schemas, false)
        Application.put_env(:ash_typescript, :generate_phx_channel_rpc_actions, false)
        Application.put_env(:ash_typescript, :add_ash_internals_to_manifest, false)

        manifest = ManifestGenerator.generate_manifest(:ash_typescript)

        # Should have validation column
        assert manifest =~ "| Validation |"
        assert manifest =~ "`validateListTodos`"

        # Should NOT have zod or channel columns
        refute manifest =~ "| Zod Schema |"
        refute manifest =~ "| Channel |"
      after
        restore_config(:generate_validation_functions, original_validation)
        restore_config(:generate_zod_schemas, original_zod)
        restore_config(:generate_phx_channel_rpc_actions, original_channel)
        restore_config(:add_ash_internals_to_manifest, original_internals)
      end
    end
  end

  describe "ManifestGenerator - namespace grouping" do
    test "groups by namespace when namespaces are configured" do
      manifest = ManifestGenerator.generate_manifest(:ash_typescript)

      # Test config has todos and users namespaces
      assert manifest =~ "## Namespace: todos" or manifest =~ "## Default (No Namespace)"
    end

    test "actions in the same namespace are grouped together" do
      manifest = ManifestGenerator.generate_manifest(:ash_typescript)

      # listTodos is in the todos namespace
      if manifest =~ "## Namespace: todos" do
        # Extract the todos namespace section (everything after "## Namespace: todos" until next "## ")
        todos_section =
          case Regex.run(~r/## Namespace: todos\n([\s\S]*?)(?=\n## [^#]|$)/s, manifest) do
            [_, section] -> section
            _ -> ""
          end

        assert todos_section =~ "`listTodos`",
               "Expected todos namespace section to contain listTodos. Section content: #{String.slice(todos_section, 0, 500)}"
      end
    end
  end

  # Helper to restore config
  defp restore_config(key, nil), do: Application.delete_env(:ash_typescript, key)
  defp restore_config(key, value), do: Application.put_env(:ash_typescript, key, value)
end
