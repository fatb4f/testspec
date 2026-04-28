package tier0

#MutationEvent: {
  action: "write" | "exec" | "network" | "git" | "service" | "session" | "display"
  path?: string
  command?: string
  allowed: bool
  reason: string
}

#MutationGuard: {
  ok: bool

  allowed_roots: [...string]
  forbidden_patterns: [...string]

  before: {
    git_status: string
  }

  after: {
    git_status: string
  }

  events: [...#MutationEvent]
  violations: [...#MutationEvent]
}
