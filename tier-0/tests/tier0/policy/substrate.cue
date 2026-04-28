package tier0

#ToolClass: "runtime" | "policy" | "controller" | "lint" | "scm" | "bootstrap"

#RequirementLevel: "hard" | "phase" | "optional"

#ToolSource: "system" | "fixture_projected" | "bootstrap_managed" | "host_provided"

#ToolRequirement: {
	key: string
	command: string
	class: #ToolClass
	level: #RequirementLevel
	phases: [...string]
	reason: string
	source: #ToolSource | *"system"
}

#CommandRequirement: {
	key: string
	command: string
	phase: string
	level: #RequirementLevel
	reason: string
}

#Tier0Substrate: {
	tools: [...#ToolRequirement]
	commands: [...#CommandRequirement]
}

#DefaultTier0Substrate: #Tier0Substrate & {
	tools: [
		{
			key: "bash"
			command: "bash"
			class: "runtime"
			level: "hard"
			phases: ["clean_bash_load", "bash_to_zsh"]
			reason: "clean bash and non-interactive execution"
		},
		{
			key: "zsh"
			command: "zsh"
			class: "runtime"
			level: "hard"
			phases: ["clean_zsh_load", "login_zsh_no_hang", "zsh_to_bash"]
			reason: "login shell and shell transition checks"
		},
		{
			key: "python3"
			command: "python3"
			class: "runtime"
			level: "hard"
			phases: ["path_resolution", "loader_transition_contract"]
			reason: "JSON report generation and status publication"
		},
		{
			key: "git"
			command: "git"
			class: "scm"
			level: "phase"
			phases: ["git_refresh_status"]
			reason: "git substrate observation"
		},
		{
			key: "jq"
			command: "jq"
			class: "runtime"
			level: "phase"
			phases: ["audit_gate", "doctor_graph", "dotctl_check"]
			reason: "JSON inspection for control-plane commands"
		},
		{
			key: "cue"
			command: "cue"
			class: "policy"
			level: "phase"
			source: "fixture_projected"
			phases: ["precommit_lint", "audit_gate", "doctor_graph", "git_refresh_status", "dotctl_check"]
			reason: "CUE policy validation"
		},
		{
			key: "just"
			command: "just"
			class: "controller"
			level: "phase"
			source: "fixture_projected"
			phases: ["precommit_lint"]
			reason: "operator recipe execution"
		},
		{
			key: "gh"
			command: "gh"
			class: "bootstrap"
			level: "phase"
			source: "fixture_projected"
			phases: ["bootstrap_dry_run"]
			reason: "bootstrap dry-run path observes GitHub release helper requirement"
		},
		{
			key: "shellcheck"
			command: "shellcheck"
			class: "lint"
			level: "phase"
			source: "system"
			phases: ["precommit_lint"]
			reason: "shell lint gate"
		},
		{
			key: "shellharden"
			command: "shellharden"
			class: "lint"
			level: "phase"
			source: "fixture_projected"
			phases: ["precommit_lint", "dotctl_check"]
			reason: "shell hardening gate"
		},
		{
			key: "shfmt"
			command: "shfmt"
			class: "lint"
			level: "phase"
			source: "system"
			phases: ["precommit_lint"]
			reason: "shell formatting gate"
		},
		{
			key: "bats"
			command: "bats"
			class: "lint"
			level: "phase"
			source: "system"
			phases: ["precommit_lint"]
			reason: "Bats shell tests"
		},
		{
			key: "shellspec"
			command: "shellspec"
			class: "lint"
			level: "phase"
			source: "fixture_projected"
			phases: ["precommit_lint"]
			reason: "ShellSpec shell tests"
		},
	]

	commands: [
		{
			key: "just.precommit-lint"
			command: "just precommit-lint"
			phase: "precommit_lint"
			level: "phase"
			reason: "precommit lint gate operator entrypoint"
		},
		{
			key: "dotctl.audit.run"
			command: "dotctl audit run"
			phase: "audit_gate"
			level: "phase"
			reason: "audit gate command surface"
		},
		{
			key: "dotctl.doctor.check"
			command: "dotctl doctor check"
			phase: "doctor_graph"
			level: "phase"
			reason: "doctor graph command surface"
		},
		{
			key: "dotctl.git.refresh"
			command: "dotctl git refresh"
			phase: "git_refresh_status"
			level: "phase"
			reason: "git substrate refresh command surface"
		},
		{
			key: "dotctl.check"
			command: "dotctl check"
			phase: "dotctl_check"
			level: "phase"
			reason: "aggregate Tier-0 control-plane check"
		},
		{
			key: "yadm.bootstrap.dry-run"
			command: "DRY_RUN=1 yadm bootstrap"
			phase: "bootstrap_dry_run"
			level: "phase"
			reason: "bootstrap dry-run command surface"
		},
	]
}
