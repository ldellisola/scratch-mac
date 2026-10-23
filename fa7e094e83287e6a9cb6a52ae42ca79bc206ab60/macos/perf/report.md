## Performance (milliseconds; idle_cpu_pct is a percentage of one core, idle_wakeups a count)

| Metric | Result | Baseline | Budget | Verdict | Notes |
|---|---|---|---|---|---|
| launch_overhead_ms | 70.29 | - | 150 | WARN | no baseline |
| keystroke_ms | 5.46 | 6.3 | 8 | OK |  |
| scroll_frame_ms | 0.73 | 5.8 | 8 | OK |  |
| switch_small_ms | 22.77 | 17.6 | 12 | FAIL | 29% slower than the baseline; over budget |
| switch_huge_ms | 36.52 | 65.9 | 50 | OK |  |
| paste_code_ms | 89.77 | 85.3 | 50 | WARN | over budget |
| idle_cpu_pct | 0.36 | - | 1 | WARN | no baseline |
| launch_ms | 1052 | 776.1 | - | INFO | reported, not checked |
| launch_reference_ms | 778.42 | - | - | INFO | reported, not checked |
| launch_difference_ms | 273.58 | - | - | INFO | reported, not checked |
| scroll_frame_wall_ms | 0.73 | - | - | INFO | reported, not checked |
| scroll_frame_p95_ms | 17.13 | - | - | INFO | reported, not checked |
| scroll_frame_max_ms | 27.92 | - | - | INFO | reported, not checked |
| idle_wakeups | 3 | - | - | INFO | reported, not checked |
| launch_phase_main_ms | 168.15 | - | - | INFO | reported, not checked |
| launch_phase_storage_ms | 290.75 | - | - | INFO | reported, not checked |
| launch_phase_restore_ms | 686.75 | - | - | INFO | reported, not checked |
| launch_phase_window_ms | 782.45 | - | - | INFO | reported, not checked |
| launch_phase_firstFrame_ms | 1115.85 | - | - | INFO | reported, not checked |

Result: FAIL
