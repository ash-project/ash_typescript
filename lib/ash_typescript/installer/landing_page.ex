# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

if Code.ensure_loaded?(Igniter) do
  defmodule AshTypescript.Installer.LandingPage do
    @moduledoc false

    @hexdocs "https://hexdocs.pm/ash_typescript"

    @doc "Returns the landing page animation module as a TypeScript string."
    def animation_module do
      """
      // AshTypescript landing page animation
      // Typewriter effect with syntax highlighting, inspired by ash-hq.org

      const HEXDOCS = "#{@hexdocs}";

      interface Stage {
        name: string;
        description: string;
        docsPath: string;
        elixir: string;
        typescript: string;
      }

      const stages: Stage[] = [
        {
          name: "Type-Safe RPC",
          description: "Auto-generated TypeScript functions for every Ash action with full type inference.",
          docsPath: "/first-rpc-action.html",
          elixir: `use Ash.Domain,
        extensions: [AshTypescript.Rpc]

      typescript_rpc do
        resource MyApp.Todo do
          rpc_action :list_todos, :read
          rpc_action :create_todo, :create
          rpc_action :update_todo, :update
        end
      end`,
          typescript: `import { listTodos, createTodo } from "./ash_rpc";

      const result = await listTodos({
        fields: ["id", "title", { user: ["name"] }],
        filter: { completed: { eq: false } },
        sort: [{ field: "insertedAt", order: "desc" }],
      });

      if (result.success) {
        // result.data is fully typed!
        result.data.forEach(todo => {
          console.log(todo.title, todo.user.name);
        });
      }`,
        },
        {
          name: "Typed Controllers",
          description: "Typed route helpers and fetch functions for Phoenix controllers.",
          docsPath: "/typed-controllers.html",
          elixir: `use AshTypescript.TypedController

      typed_controller do
        module_name MyAppWeb.SessionController

        get :current_user do
          run fn conn, _params ->
            json(conn, current_user(conn))
          end
        end

        post :login do
          argument :email, :string, allow_nil?: false
          argument :password, :string, allow_nil?: false
          run fn conn, params ->
            # authenticate and respond
          end
        end
      end`,
          typescript: `import {
        currentUserPath,
        login,
      } from "./routes";

      // Typed path helpers
      currentUserPath(); // => "/session/current_user"

      // Typed fetch functions for mutations
      const result = await login({
        email: "user@example.com",
        password: "secret",
        headers: buildCSRFHeaders(),
      });`,
        },
        {
          name: "Typed Channels",
          description: "Type-safe Phoenix channel event subscriptions with Ash PubSub.",
          docsPath: "/typed-channels.html",
          elixir: `# Resource with PubSub
      pub_sub do
        prefix "posts"
        publish :create, [:id],
          event: "post_created",
          transform: :post_summary
      end

      # Typed channel definition
      typed_channel do
        topic "org:*"

        resource MyApp.Post do
          publish :post_created
          publish :post_updated
        end
      end`,
          typescript: `import {
        createOrgChannel,
        onOrgChannelMessages,
      } from "./ash_typed_channels";

      const channel = createOrgChannel(socket, orgId);

      const refs = onOrgChannelMessages(channel, {
        post_created: (payload) => {
          // payload type inferred from calculation!
          addPost(payload.id, payload.title);
        },
        post_updated: (payload) => {
          updatePost(payload.id, payload.title);
        },
      });`,
        },
        {
          name: "Field Selection",
          description: "Request exactly the fields you need with full type narrowing.",
          docsPath: "/field-selection.html",
          elixir: `# Define your resource with relationships
      attributes do
        uuid_primary_key :id
        attribute :title, :string, public?: true
        attribute :body, :string, public?: true
        attribute :view_count, :integer, public?: true
      end

      relationships do
        belongs_to :author, MyApp.User, public?: true
      end

      calculations do
        calculate :reading_time, :integer,
          expr(string_length(body) / 200)
      end`,
          typescript: `// Only fetch what you need - response is narrowed
      const posts = await listPosts({
        fields: [
          "id",
          "title",
          "readingTime",
          { author: ["name", "avatarUrl"] },
        ],
      });

      // TypeScript knows the exact shape:
      posts.data[0].title;             // string ✓
      posts.data[0].readingTime;       // number ✓
      posts.data[0].author.name;       // string ✓
      posts.data[0].body;              // Error! Not selected`,
        },
      ];

      // Elixir syntax highlighting
      function highlightElixir(code: string): string {
        const tokens: { start: number; end: number; cls: string }[] = [];
        const patterns: [RegExp, string][] = [
          [/#[^\\n]*/g, "text-gray-500"],
          [/"[^"]*"/g, "text-yellow-400"],
          [/\\b(defmodule|def|defp|do|end|use|fn|if|else|case|cond|with|for|unless|import|alias|require)\\b/g, "text-pink-400"],
          [/\\b(true|false|nil)\\b/g, "text-purple-400"],
          [/(:[a-zA-Z_][a-zA-Z0-9_?!]*)/g, "text-cyan-400"],
          [/\\b([A-Z][a-zA-Z0-9]*(\\.[A-Z][a-zA-Z0-9]*)*)\\b/g, "text-blue-400"],
          [/(\\|>|->|<-|=>)/g, "text-pink-400"],
        ];
        for (const [re, cls] of patterns) {
          let m: RegExpExecArray | null;
          while ((m = re.exec(code)) !== null) {
            const overlaps = tokens.some(t => m!.index < t.end && m!.index + m![0].length > t.start);
            if (!overlaps) tokens.push({ start: m.index, end: m.index + m[0].length, cls });
          }
        }
        tokens.sort((a, b) => a.start - b.start);
        let result = "";
        let pos = 0;
        for (const t of tokens) {
          if (t.start > pos) result += esc(code.slice(pos, t.start));
          result += `<span class="${t.cls}">${esc(code.slice(t.start, t.end))}</span>`;
          pos = t.end;
        }
        if (pos < code.length) result += esc(code.slice(pos));
        return result;
      }

      // TypeScript syntax highlighting
      function highlightTS(code: string): string {
        const tokens: { start: number; end: number; cls: string }[] = [];
        const patterns: [RegExp, string][] = [
          [/\\/\\/[^\\n]*/g, "text-gray-500"],
          [/"[^"]*"/g, "text-yellow-400"],
          [/`[^`]*`/g, "text-yellow-400"],
          [/\\b(import|from|export|const|let|var|function|return|if|else|async|await|new|typeof|interface|type)\\b/g, "text-pink-400"],
          [/\\b(true|false|null|undefined)\\b/g, "text-purple-400"],
          [/(=>)/g, "text-pink-400"],
        ];
        for (const [re, cls] of patterns) {
          let m: RegExpExecArray | null;
          while ((m = re.exec(code)) !== null) {
            const overlaps = tokens.some(t => m!.index < t.end && m!.index + m![0].length > t.start);
            if (!overlaps) tokens.push({ start: m.index, end: m.index + m[0].length, cls });
          }
        }
        tokens.sort((a, b) => a.start - b.start);
        let result = "";
        let pos = 0;
        for (const t of tokens) {
          if (t.start > pos) result += esc(code.slice(pos, t.start));
          result += `<span class="${t.cls}">${esc(code.slice(t.start, t.end))}</span>`;
          pos = t.end;
        }
        if (pos < code.length) result += esc(code.slice(pos));
        return result;
      }

      function esc(s: string): string {
        return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
      }

      // Typewriter engine
      function typewrite(
        el: HTMLElement,
        highlighted: string,
        onComplete: () => void,
        signal: { cancelled: boolean },
      ): void {
        // Build a flat list of characters with their HTML wrapping
        const chars: string[] = [];
        let inTag = false;
        let tagBuffer = "";
        let openTags: string[] = [];

        for (let i = 0; i < highlighted.length; i++) {
          const ch = highlighted[i];
          if (ch === "<") {
            inTag = true;
            tagBuffer = "<";
            continue;
          }
          if (inTag) {
            tagBuffer += ch;
            if (ch === ">") {
              inTag = false;
              if (tagBuffer.startsWith("</")) {
                openTags.pop();
              } else {
                openTags.push(tagBuffer);
              }
            }
            continue;
          }
          // Handle HTML entities as single visible characters
          let visibleChar = ch;
          if (ch === "&") {
            const semiIdx = highlighted.indexOf(";", i);
            if (semiIdx !== -1 && semiIdx - i < 8) {
              visibleChar = highlighted.slice(i, semiIdx + 1);
              i = semiIdx;
            }
          }
          let wrapped = visibleChar;
          for (const tag of openTags) {
            const cls = tag.match(/class="([^"]*)"/)?.[1] || "";
            wrapped = `<span class="${cls}">${wrapped}</span>`;
          }
          chars.push(wrapped);
        }

        let idx = 0;
        el.innerHTML = '<span class="inline-block w-[2px] h-[1.1em] bg-primary align-text-bottom animate-pulse"></span>';

        function step() {
          if (signal.cancelled) return;
          if (idx >= chars.length) {
            el.innerHTML = highlighted;
            onComplete();
            return;
          }
          // Insert character before cursor
          const cursor = el.querySelector("span:last-child")!;
          cursor.insertAdjacentHTML("beforebegin", chars[idx]);
          idx++;

          const c = chars[idx - 1];
          const isNewline = c.includes("\\n") || c === "\\n";
          const isSpace = c === " " || c.endsWith("> </span>");
          const delay = isNewline ? 80 : isSpace ? 15 : 25 + Math.random() * 15;
          setTimeout(step, delay);
        }
        step();
      }

      // Main initialization
      export function initLandingPage(container: HTMLElement): () => void {
        let currentStage = 0;
        let signal = { cancelled: false };
        let autoTimer: ReturnType<typeof setTimeout> | null = null;
        const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

        container.innerHTML = buildHTML();
        const elixirEl = container.querySelector<HTMLElement>("#elixir-code")!;
        const tsEl = container.querySelector<HTMLElement>("#ts-code")!;
        const descEl = container.querySelector<HTMLElement>("#stage-description")!;
        const docsLink = container.querySelector<HTMLAnchorElement>("#stage-docs-link")!;
        const dots = container.querySelectorAll<HTMLElement>(".stage-dot");
        const tsPanel = container.querySelector<HTMLElement>("#ts-panel")!;

        function showStage(index: number) {
          signal.cancelled = true;
          signal = { cancelled: false };
          if (autoTimer) clearTimeout(autoTimer);
          currentStage = index;
          const stage = stages[index];

          // Update dots
          dots.forEach((dot, i) => {
            dot.classList.toggle("bg-primary", i === index);
            dot.classList.toggle("opacity-100", i === index);
            dot.classList.toggle("bg-base-content", i !== index);
            dot.classList.toggle("opacity-30", i !== index);
            dot.classList.toggle("scale-125", i === index);
          });

          // Update description
          descEl.textContent = stage.description;
          docsLink.href = HEXDOCS + stage.docsPath;

          // Reset panels — hide TS panel entirely (no layout space)
          tsPanel.hidden = true;
          tsPanel.style.opacity = "0";

          const elixirHL = highlightElixir(stage.elixir);
          const tsHL = highlightTS(stage.typescript);

          if (reducedMotion) {
            elixirEl.innerHTML = elixirHL;
            tsEl.innerHTML = tsHL;
            tsPanel.hidden = false;
            tsPanel.style.opacity = "1";
            autoTimer = setTimeout(() => showStage((currentStage + 1) % stages.length), 6000);
          } else {
            typewrite(elixirEl, elixirHL, () => {
              if (signal.cancelled) return;
              tsPanel.hidden = false;
              requestAnimationFrame(() => { tsPanel.style.opacity = "1"; });
              typewrite(tsEl, tsHL, () => {
                if (signal.cancelled) return;
                autoTimer = setTimeout(() => showStage((currentStage + 1) % stages.length), 4000);
              }, signal);
            }, signal);
          }
        }

        // Dot click handlers
        dots.forEach((dot, i) => {
          dot.addEventListener("click", () => showStage(i));
        });

        // Start
        showStage(0);

        // Cleanup function
        return () => {
          signal.cancelled = true;
          if (autoTimer) clearTimeout(autoTimer);
        };
      }

      function buildHTML(): string {
        const dotHTML = stages.map((s, i) =>
          `<button class="stage-dot w-3 h-3 rounded-full transition-all duration-300 cursor-pointer ${i === 0 ? "bg-primary opacity-100 scale-125" : "bg-base-content opacity-30"}" title="${s.name}"></button>`
        ).join("");

        return `
          <div class="mb-12">
            <div class="flex items-center justify-between mb-4">
              <div class="flex gap-2 items-center">${dotHTML}</div>
              <a id="stage-docs-link" href="${HEXDOCS}" target="_blank" rel="noopener noreferrer" class="text-sm text-primary hover:underline">View docs &rarr;</a>
            </div>
            <p id="stage-description" class="text-sm opacity-70 mb-4">${stages[0].description}</p>
            <div class="space-y-3">
              <div class="relative">
                <div class="absolute top-2 right-3 text-xs opacity-40 font-mono select-none">Elixir</div>
                <pre class="bg-base-300 rounded-lg p-4 pt-8 text-sm font-mono leading-relaxed overflow-x-auto"><code id="elixir-code" class="text-gray-300"></code></pre>
              </div>
              <div id="ts-panel" class="relative transition-opacity duration-500" style="opacity:0" hidden>
                <div class="absolute top-2 right-3 text-xs opacity-40 font-mono select-none">TypeScript</div>
                <pre class="bg-base-300 rounded-lg p-4 pt-8 text-sm font-mono leading-relaxed overflow-x-auto"><code id="ts-code" class="text-gray-300"></code></pre>
              </div>
            </div>
          </div>`;
      }
      """
    end

    @doc "Returns the page shell for JSX frameworks (React/Solid)."
    def page_jsx do
      """
          <div className="min-h-screen bg-base-100 text-base-content">
            <div className="max-w-5xl mx-auto px-6 py-12">
              <div className="flex items-center gap-5 mb-8">
                <img
                  src="https://raw.githubusercontent.com/ash-project/ash_typescript/main/logos/ash-typescript.png"
                  alt="AshTypescript"
                  className="w-16 h-16"
                />
                <div>
                  <h1 className="text-4xl font-bold">AshTypescript</h1>
                  <p className="text-lg opacity-70">End-to-end type safety from Ash to TypeScript</p>
                </div>
              </div>

              <section className="mb-10">
                <div className="flex flex-wrap items-center gap-3 mb-5">
                  <h2 className="text-2xl font-bold">Main Features</h2>
                  <div className="flex-1"></div>
                  <a href="#{@hexdocs}" target="_blank" rel="noopener noreferrer" className="btn btn-primary btn-sm">
                    <svg xmlns="http://www.w3.org/2000/svg" className="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M2 3h6a4 4 0 0 1 4 4v14a3 3 0 0 0-3-3H2z"/><path d="M22 3h-6a4 4 0 0 0-4 4v14a3 3 0 0 1 3-3h7z"/></svg>
                    Docs
                  </a>
                  <a href="https://github.com/ash-project/ash_typescript" target="_blank" rel="noopener noreferrer" className="btn btn-ghost btn-sm">
                    <svg xmlns="http://www.w3.org/2000/svg" className="w-4 h-4" viewBox="0 0 24 24" fill="currentColor"><path d="M12 0c-6.626 0-12 5.373-12 12 0 5.302 3.438 9.8 8.207 11.387.599.111.793-.261.793-.577v-2.234c-3.338.726-4.033-1.416-4.033-1.416-.546-1.387-1.333-1.756-1.333-1.756-1.089-.745.083-.729.083-.729 1.205.084 1.839 1.237 1.839 1.237 1.07 1.834 2.807 1.304 3.492.997.107-.775.418-1.305.762-1.604-2.665-.305-5.467-1.334-5.467-5.931 0-1.311.469-2.381 1.236-3.221-.124-.303-.535-1.524.117-3.176 0 0 1.008-.322 3.301 1.23.957-.266 1.983-.399 3.003-.404 1.02.005 2.047.138 3.006.404 2.291-1.552 3.297-1.23 3.297-1.23.653 1.653.242 2.874.118 3.176.77.84 1.235 1.911 1.235 3.221 0 4.609-2.807 5.624-5.479 5.921.43.372.823 1.102.823 2.222v3.293c0 .319.192.694.801.576 4.765-1.589 8.199-6.086 8.199-11.386 0-6.627-5.373-12-12-12z"/></svg>
                    GitHub
                  </a>
                </div>
                <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-3">
                  #{feature_card_jsx("Type-Safe RPC", "Auto-generated typed functions for every Ash action.", "/first-rpc-action.html")}
                  #{feature_card_jsx("Typed Controllers", "Typed route helpers for Phoenix controllers.", "/typed-controllers.html")}
                  #{feature_card_jsx("Typed Channels", "Typed event subscriptions for Phoenix channels.", "/typed-channels.html")}
                  #{feature_card_jsx("Zod Validation", "Generated Zod schemas for form validation.", "/form-validation.html")}
                </div>
              </section>

              <div id="animation-container"></div>
            </div>
          </div>
      """
    end

    @doc "Returns the page shell for Vue."
    def page_vue do
      {script_section(), template_section()}
    end

    @doc "Returns the page shell for Svelte."
    def page_svelte do
      {svelte_script_section(), svelte_template_section()}
    end

    # -- Private helpers --

    defp feature_card_jsx(title, description, docs_path) do
      ~s"""
              <a href="#{@hexdocs}#{docs_path}" target="_blank" rel="noopener noreferrer" className="card bg-base-200 hover:bg-base-300 transition-colors cursor-pointer">
                    <div className="card-body">
                      <h3 className="card-title text-base">#{title}</h3>
                      <p className="text-sm opacity-70">#{description}</p>
                      <div className="text-sm text-primary mt-1">View docs &rarr;</div>
                    </div>
                  </a>
      """
    end

    defp hero_html do
      """
          <div class="flex items-center gap-5 mb-8">
            <img
              src="https://raw.githubusercontent.com/ash-project/ash_typescript/main/logos/ash-typescript.png"
              alt="AshTypescript"
              class="w-16 h-16"
            />
            <div>
              <h1 class="text-4xl font-bold">AshTypescript</h1>
              <p class="text-lg opacity-70">End-to-end type safety from Ash to TypeScript</p>
            </div>
          </div>
      """
    end

    defp features_and_links_html do
      book_svg =
        ~s|<svg xmlns="http://www.w3.org/2000/svg" class="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M2 3h6a4 4 0 0 1 4 4v14a3 3 0 0 0-3-3H2z"/><path d="M22 3h-6a4 4 0 0 0-4 4v14a3 3 0 0 1 3-3h7z"/></svg>|

      github_svg =
        ~s|<svg xmlns="http://www.w3.org/2000/svg" class="w-4 h-4" viewBox="0 0 24 24" fill="currentColor"><path d="M12 0c-6.626 0-12 5.373-12 12 0 5.302 3.438 9.8 8.207 11.387.599.111.793-.261.793-.577v-2.234c-3.338.726-4.033-1.416-4.033-1.416-.546-1.387-1.333-1.756-1.333-1.756-1.089-.745.083-.729.083-.729 1.205.084 1.839 1.237 1.839 1.237 1.07 1.834 2.807 1.304 3.492.997.107-.775.418-1.305.762-1.604-2.665-.305-5.467-1.334-5.467-5.931 0-1.311.469-2.381 1.236-3.221-.124-.303-.535-1.524.117-3.176 0 0 1.008-.322 3.301 1.23.957-.266 1.983-.399 3.003-.404 1.02.005 2.047.138 3.006.404 2.291-1.552 3.297-1.23 3.297-1.23.653 1.653.242 2.874.118 3.176.77.84 1.235 1.911 1.235 3.221 0 4.609-2.807 5.624-5.479 5.921.43.372.823 1.102.823 2.222v3.293c0 .319.192.694.801.576 4.765-1.589 8.199-6.086 8.199-11.386 0-6.627-5.373-12-12-12z"/></svg>|

      """
          <section class="mb-10">
            <div class="flex flex-wrap items-center gap-3 mb-5">
              <h2 class="text-2xl font-bold">Main Features</h2>
              <div class="flex-1"></div>
              <a href="#{@hexdocs}" target="_blank" rel="noopener noreferrer" class="btn btn-primary btn-sm">
                #{book_svg} Docs
              </a>
              <a href="https://github.com/ash-project/ash_typescript" target="_blank" rel="noopener noreferrer" class="btn btn-ghost btn-sm">
                #{github_svg} GitHub
              </a>
            </div>
            <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-3">
              #{feature_card_html("Type-Safe RPC", "Auto-generated typed functions for every Ash action.", "/first-rpc-action.html")}
              #{feature_card_html("Typed Controllers", "Typed route helpers for Phoenix controllers.", "/typed-controllers.html")}
              #{feature_card_html("Typed Channels", "Typed event subscriptions for Phoenix channels.", "/typed-channels.html")}
              #{feature_card_html("Zod Validation", "Generated Zod schemas for form validation.", "/form-validation.html")}
            </div>
          </section>
      """
    end

    defp feature_card_html(title, description, docs_path) do
      """
            <a href="#{@hexdocs}#{docs_path}" target="_blank" rel="noopener noreferrer" class="card bg-base-200 hover:bg-base-300 transition-colors cursor-pointer">
              <div class="card-body">
                <h3 class="card-title text-base">#{title}</h3>
                <p class="text-sm opacity-70">#{description}</p>
                <div class="text-sm text-primary mt-1">View docs &rarr;</div>
              </div>
            </a>
      """
    end

    defp script_section do
      """
      <script setup lang="ts">
      import { onMounted, onUnmounted, ref } from "vue";
      import { initLandingPage } from "./animation";

      const animContainer = ref<HTMLElement | null>(null);
      let cleanup: (() => void) | null = null;

      onMounted(() => {
        if (animContainer.value) {
          cleanup = initLandingPage(animContainer.value);
        }
      });

      onUnmounted(() => {
        if (cleanup) cleanup();
      });
      </script>
      """
    end

    defp template_section do
      """
      <template>
        <div class="min-h-screen bg-base-100 text-base-content">
          <div class="max-w-5xl mx-auto px-6 py-12">
            #{hero_html()}
            #{features_and_links_html()}
            <div ref="animContainer"></div>
          </div>
        </div>
      </template>
      """
    end

    defp svelte_script_section do
      """
      <script lang="ts">
        import { onMount, onDestroy } from "svelte";
        import { initLandingPage } from "./animation";

        let animContainer: HTMLElement;
        let cleanup: (() => void) | null = null;

        onMount(() => {
          if (animContainer) {
            cleanup = initLandingPage(animContainer);
          }
        });

        onDestroy(() => {
          if (cleanup) cleanup();
        });
      </script>
      """
    end

    defp svelte_template_section do
      """
      <div class="min-h-screen bg-base-100 text-base-content">
        <div class="max-w-5xl mx-auto px-6 py-12">
          #{hero_html()}
          #{features_and_links_html()}
          <div bind:this={animContainer}></div>
        </div>
      </div>
      """
    end
  end
end
