package tier0

#Mode: "unit" | "integration"
#Distro: "debian-base" | "arch-base" | "unsupported" | string

#PhaseResult: {
  name: string
  ok: bool
  exit: int & >=0
  mode: #Mode
  distro: #Distro
  readonly: true
  command: string
  classification: string
  reason: string
  stderr_excerpt: string
  preflight_failed_check: string
  preflight_failed_reason: string
  execution?: {
    ok: bool
    exit: int & >=0
    classification: string
    failed_check?: string
    reason: string
    stdout_excerpt?: string
    stderr_excerpt: string
  }
  preflight: {
    ok: bool
    env?: {
      home: string
      path: [...string]
      xdg_bin_home: string
      xdg_data_bin: string
      tool_path_home: string
      tier0_system_path: string
      pwd: string
      commands: {
        dotctl: string
        yadm: string
        just: string
      }
    }
    checks: [...{
      name: string
      ok: bool
      reason: string
      command?: string
      resolved?: string
      source?: string
    }]
  }
}

#RobustnessReport: {
  schema: "tier0.robustness.report.v0"
  backend?: #BackendReport
  mutation_guard?: #MutationGuard
  chaos?: {
    enabled: bool
    ok: bool
    case?: string
    mutation?: string
    target?: string
    expected?: {
      phase: string
      classification: string
      failed_check?: string
    }
  }
  distro: #Distro
  mode: #Mode
  summary: {
    ok: bool
    count: int & >=0
    expected_count: int & >=0
    failed: [...string]
  }
  phases: [...#PhaseResult]
}
