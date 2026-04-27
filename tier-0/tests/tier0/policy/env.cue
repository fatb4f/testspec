package tier0

#EnvSnapshot: {
  home: string
  path: [...string]
  xdg_bin_home: string
  xdg_data_bin: string
  tool_path_home: string
  tier0_system_path: string
  backend: string
  pwd: string
  commands: {
    dotctl: string
    yadm: string
    just: string
  }
}

#LoaderTransition: {
  schema: "tier0.loader-transition.observed.v0"
  backend?: #BackendReport
  before: #EnvSnapshot
  after: #EnvSnapshot

  invariants: {
    tool_path_preserved: true
    xdg_bin_preserved: true
    fixture_tools_first: true
    dotctl_resolves: true
    yadm_resolves: true
    just_resolves: true
  }
}
