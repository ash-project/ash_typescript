# SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
#
# SPDX-License-Identifier: MIT

import Config

config :git_ops,
  mix_project: Mix.Project.get!(),
  types: [types: [tidbit: [hidden?: true], important: [header: "Important Changes"]]],
  repository_url: "https://github.com/ash-project/ash_typescript",
  github_handle_lookup?: true,
  version_tag_prefix: "v",
  manage_mix_version?: true,
  manage_readme_version: true
