package tier0

#Mode: "unit" | "integration"
#Distro: "debian-base" | "arch-base" | "unsupported" | string

#PhaseResult: {
  name: string
  ok: true
  mode: #Mode
  distro: #Distro
  readonly: true
}

#RobustnessReport: {
  schema: "tier0.robustness.report.v0"
  distro: #Distro
  mode: #Mode
  summary: {
    ok: true
    count: int & >=12
  }
  phases: [...#PhaseResult]
}
