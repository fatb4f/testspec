package tier0

#ChaosCase: {
	name: string
	mutation: string
	target: string
	expected_phase: string
	expected_classification: string
	expected_failed_check?: string
}

#ChaosResult: {
	name: string
	ok: bool
	expected: {
		phase: string
		classification: string
		failed_check?: string
	}
	observed: {
		phase: string
		classification: string
		failed_check?: string
	}
}

#ChaosSuite: {
	ok: bool
	cases: [...#ChaosResult]
}
