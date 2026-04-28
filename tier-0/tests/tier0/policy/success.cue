package tier0

#SuccessfulRobustnessReport: #RobustnessReport & {
  mutation_guard: {
    ok: true
  }

  summary: {
    ok: true
    count: int & >=12
    expected_count: int & >=12
    failed: []
  }

  phases: [...{
    ok: true
  }]
}
