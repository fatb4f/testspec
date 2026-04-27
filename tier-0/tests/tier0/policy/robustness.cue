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
}

#RobustnessReport: {
  schema: "tier0.robustness.report.v0"
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
