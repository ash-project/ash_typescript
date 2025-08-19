import Config

config :git_ops,
  mix_project: Mix.Project.get!(),
  types: [types: [tidbit: [hidden?: true], important: [header: "Important Changes"]]],
  version_tag_prefix: "v",
  manage_mix_version?: true,
  manage_readme_version: true
