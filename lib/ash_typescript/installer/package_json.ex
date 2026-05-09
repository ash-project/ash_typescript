# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

if Code.ensure_loaded?(Igniter) do
  defmodule AshTypescript.Installer.PackageJson do
    @moduledoc false

    @doc """
    Ensure package.json exists and add framework-specific dependencies.
    For vite, starts with an empty package.json (phoenix_vite manages Phoenix deps).
    For esbuild, starts with Phoenix deps.
    """
    def create_package_json(igniter, "vite", framework) do
      igniter
      |> Igniter.create_or_update_file("assets/package.json", "{}\n", fn source -> source end)
      |> add_framework_deps(framework, "vite")
    end

    def create_package_json(igniter, _bundler, framework) do
      base_package_json =
        %{
          "dependencies" => %{
            "phoenix" => "file:../deps/phoenix",
            "phoenix_html" => "file:../deps/phoenix_html",
            "phoenix_live_view" => "file:../deps/phoenix_live_view",
            "topbar" => "^3.0.0"
          }
        }
        |> encode_pretty_json()

      igniter
      |> Igniter.create_or_update_file("assets/package.json", base_package_json, fn source ->
        source
      end)
      |> add_framework_deps(framework, "esbuild")
      |> update_vendor_imports()
    end

    @doc "Add esbuild as an npm dependency (for plugin-based builds that bypass the Elixir esbuild wrapper)."
    def add_esbuild_npm_dep(igniter) do
      update_package_json(igniter, fn package_json ->
        merge_package_section(package_json, "devDependencies", %{"esbuild" => "^0.24.0"})
      end)
    end

    @doc "Update package.json by applying an updater function to the parsed JSON."
    def update_package_json(igniter, updater) do
      Igniter.update_file(igniter, "assets/package.json", fn source ->
        case Jason.decode(source.content) do
          {:ok, package_json} ->
            updated_package_json = updater.(package_json)

            if updated_package_json == package_json do
              source
            else
              Rewrite.Source.update(source, :content, encode_pretty_json(updated_package_json))
            end

          {:error, _error} ->
            source
        end
      end)
    end

    @doc "Merge deps into a section of package.json (dependencies or devDependencies)."
    def merge_package_section(package_json, section, deps) when is_map(deps) do
      current_deps = Map.get(package_json, section, %{})
      Map.put(package_json, section, Map.merge(current_deps, deps))
    end

    def encode_pretty_json(data) do
      Jason.encode!(data, pretty: true) <> "\n"
    end

    # -- Private --

    defp add_framework_deps(igniter, framework, bundler) do
      deps = get_framework_deps(framework, bundler)

      update_package_json(igniter, fn package_json ->
        package_json
        |> merge_package_section("dependencies", deps.dependencies)
        |> merge_package_section("devDependencies", deps.dev_dependencies)
      end)
    end

    defp update_vendor_imports(igniter) do
      igniter
      |> Igniter.update_file("assets/js/app.js", fn source ->
        Rewrite.Source.update(source, :content, fn content ->
          String.replace(content, "../vendor/topbar", "topbar")
        end)
      end)
      |> delete_vendor_files()
    end

    defp delete_vendor_files(igniter) do
      igniter
      |> Igniter.rm("assets/vendor/topbar.js")
    end

    # Framework deps -- only the framework core + bundler plugin. No TanStack, Prism, DaisyUI.

    defp get_framework_deps("react", "vite") do
      %{
        dependencies: %{"react" => "^19.1.1", "react-dom" => "^19.1.1"},
        dev_dependencies: %{
          "@types/react" => "^19.1.13",
          "@types/react-dom" => "^19.1.9",
          "@vitejs/plugin-react" => "^4.5.0"
        }
      }
    end

    defp get_framework_deps("react", _bundler) do
      %{
        dependencies: %{"react" => "^19.1.1", "react-dom" => "^19.1.1"},
        dev_dependencies: %{
          "@types/react" => "^19.1.13",
          "@types/react-dom" => "^19.1.9"
        }
      }
    end

    defp get_framework_deps("vue", "vite") do
      %{
        dependencies: %{"vue" => "^3.5.16"},
        dev_dependencies: %{"@vitejs/plugin-vue" => "^5.2.4"}
      }
    end

    defp get_framework_deps("vue", _bundler) do
      %{
        dependencies: %{"vue" => "^3.5.16"},
        dev_dependencies: %{"esbuild-plugin-vue3" => "^0.4.2"}
      }
    end

    defp get_framework_deps("svelte", "vite") do
      %{
        dependencies: %{"svelte" => "^5.33.0"},
        dev_dependencies: %{"@sveltejs/vite-plugin-svelte" => "^5.0.3"}
      }
    end

    defp get_framework_deps("svelte", _bundler) do
      %{
        dependencies: %{"svelte" => "^5.33.0"},
        dev_dependencies: %{"esbuild-svelte" => "^0.9.3"}
      }
    end

    defp get_framework_deps("solid", "vite") do
      %{
        dependencies: %{"solid-js" => "^1.9.9"},
        dev_dependencies: %{"vite-plugin-solid" => "^2.11.9"}
      }
    end

    defp get_framework_deps("solid", _bundler) do
      %{
        dependencies: %{"solid-js" => "^1.9.9"},
        dev_dependencies: %{"esbuild-plugin-solid" => "^0.6.0"}
      }
    end
  end
end
