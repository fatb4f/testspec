package tier0

#BackendName: "headless" | "distrobox" | "kitty-run-shell"

#KittyTransportStatus: {
  outer_exit: int & >=0 & <=255
  ok: bool
  reason?: string
}

#ChildStatus: {
  status_dir: string
  status_path: string
  done_path: string
  started_path: string
  stdout_path?: string
  stderr_path?: string
  visible: bool
  done: bool
  valid: bool
  exit?: int & >=0 & <=255
  classification: "ok" |
    "command_failed" |
    "missing_tool" |
    "missing_dependency" |
    "policy_reject" |
    "timeout" |
    "missing_status" |
    "invalid_status" |
    "child_launch_failed" |
    "transport_failed" |
    "terminal_substrate_unavailable"
  failed_check?: string
  reason?: string
  stdout_excerpt?: string
  stderr_excerpt?: string
}

#GenericBackend: {
  name: "headless" | "distrobox"
  required?: bool
  ok: bool
  classification: string
  reason: string

  transport: {
    outer_exit?: int & >=0 & <=255
    ok: bool
    reason?: string
    name: string
    kitten: {
      found: bool
      path: string | *""
    }
    kitty: {
      present: bool
      socket?: string
      window_id?: string
    }
    shell: {
      name: string
      mode: "run-shell"
    }
  }

  child?: #ChildStatus | *null

  fixture: {
    home: string
    tool_path_home: string
    xdg_bin_home: string
  }
}

#KittyRunShellBackend: {
  name: "kitty-run-shell"
  required?: bool | *false
  transport: #KittyTransportStatus
  child: #ChildStatus
  ok: child.classification == "ok"
  classification: child.classification
  reason?: child.reason

  fixture: {
    home: string
    tool_path_home: string
    xdg_bin_home: string
  }
}

#BackendReport: #GenericBackend | #KittyRunShellBackend
