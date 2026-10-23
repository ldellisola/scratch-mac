## Performance (milliseconds; idle_cpu_pct is a percentage of one core, idle_wakeups a count)

| Metric | Result | Baseline | Budget | Verdict | Notes |
|---|---|---|---|---|---|
| launch_overhead_ms | 283.1 | - | 150 | WARN | no baseline; over budget |
| keystroke_ms | 4.87 | 6.3 | 8 | OK |  |
| scroll_frame_ms | 4.64 | 5.8 | 8 | OK |  |
| switch_small_ms | 15.48 | 17.6 | 12 | WARN | over budget |
| switch_huge_ms | 50.73 | 65.9 | 50 | WARN | over budget |
| paste_code_ms | 103.88 | 85.3 | 50 | FAIL | over 2x the budget; 22% slower than the baseline; over budget |
| idle_cpu_pct | 0.13 | - | 1 | WARN | no baseline |
| launch_ms | 840.83 | 776.1 | - | INFO | reported, not checked |
| launch_reference_ms | 348.1 | - | - | INFO | reported, not checked |
| launch_difference_ms | 492.73 | - | - | INFO | reported, not checked |
| scroll_frame_wall_ms | 8.81 | - | - | INFO | reported, not checked |
| scroll_frame_p95_ms | 14.51 | - | - | INFO | reported, not checked |
| scroll_frame_max_ms | 20.35 | - | - | INFO | reported, not checked |
| idle_wakeups | 3 | - | - | INFO | reported, not checked |
| launch_phase_main_ms | 118.8 | - | - | INFO | reported, not checked |
| launch_phase_storage_ms | 217.2 | - | - | INFO | reported, not checked |
| launch_phase_restore_ms | 527.45 | - | - | INFO | reported, not checked |
| launch_phase_window_ms | 620.75 | - | - | INFO | reported, not checked |
| launch_phase_firstFrame_ms | 890.3 | - | - | INFO | reported, not checked |

Result: FAIL
