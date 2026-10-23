## Performance (milliseconds; idle_cpu_pct is a percentage of one core, idle_wakeups a count)

| Metric | Result | Baseline | Budget | Verdict | Notes |
|---|---|---|---|---|---|
| launch_overhead_ms | 150.96 | - | 150 | WARN | no baseline; over budget |
| keystroke_ms | 3.61 | 6.3 | 8 | OK |  |
| scroll_frame_ms | 0.29 | 5.8 | 8 | OK |  |
| switch_small_ms | 9.02 | 17.6 | 12 | OK |  |
| switch_huge_ms | 28.45 | 65.9 | 50 | OK |  |
| paste_code_ms | 53.38 | 85.3 | 50 | WARN | over budget |
| idle_cpu_pct | 0.08 | - | 1 | WARN | no baseline |
| launch_ms | 558.96 | 776.1 | - | INFO | reported, not checked |
| launch_reference_ms | 318.54 | - | - | INFO | reported, not checked |
| launch_difference_ms | 240.43 | - | - | INFO | reported, not checked |
| scroll_frame_wall_ms | 0.29 | - | - | INFO | reported, not checked |
| scroll_frame_p95_ms | 3.91 | - | - | INFO | reported, not checked |
| scroll_frame_max_ms | 6.39 | - | - | INFO | reported, not checked |
| idle_wakeups | 4 | - | - | INFO | reported, not checked |
| launch_phase_main_ms | 83.3 | - | - | INFO | reported, not checked |
| launch_phase_storage_ms | 140.6 | - | - | INFO | reported, not checked |
| launch_phase_restore_ms | 363 | - | - | INFO | reported, not checked |
| launch_phase_window_ms | 420.35 | - | - | INFO | reported, not checked |
| launch_phase_firstFrame_ms | 617.55 | - | - | INFO | reported, not checked |

Result: PASS
