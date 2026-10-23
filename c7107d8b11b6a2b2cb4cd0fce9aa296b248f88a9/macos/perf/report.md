## Performance (milliseconds; idle_cpu_pct is a percentage of one core, idle_wakeups a count)

| Metric | Result | Baseline | Budget | Verdict | Notes |
|---|---|---|---|---|---|
| launch_overhead_ms | 432.03 | - | 150 | FAIL | over 2x the budget; no baseline; over budget |
| keystroke_ms | 6.13 | 6.3 | 8 | OK |  |
| scroll_frame_ms | 0.61 | 5.8 | 8 | OK |  |
| switch_small_ms | 13.21 | 17.6 | 12 | WARN | over budget |
| switch_huge_ms | 34.03 | 65.9 | 50 | OK |  |
| paste_code_ms | 83.68 | 85.3 | 50 | WARN | over budget |
| idle_cpu_pct | 0.39 | - | 1 | WARN | no baseline |
| launch_ms | 1021.49 | 776.1 | - | INFO | reported, not checked |
| launch_reference_ms | 589.46 | - | - | INFO | reported, not checked |
| scroll_frame_wall_ms | 0.62 | - | - | INFO | reported, not checked |
| scroll_frame_p95_ms | 13.56 | - | - | INFO | reported, not checked |
| scroll_frame_max_ms | 27.68 | - | - | INFO | reported, not checked |
| idle_wakeups | 5 | - | - | INFO | reported, not checked |
| launch_phase_main_ms | 130.4 | - | - | INFO | reported, not checked |
| launch_phase_storage_ms | 214.8 | - | - | INFO | reported, not checked |
| launch_phase_restore_ms | 546.85 | - | - | INFO | reported, not checked |
| launch_phase_window_ms | 647.95 | - | - | INFO | reported, not checked |
| launch_phase_firstFrame_ms | 918.2 | - | - | INFO | reported, not checked |

Result: FAIL
