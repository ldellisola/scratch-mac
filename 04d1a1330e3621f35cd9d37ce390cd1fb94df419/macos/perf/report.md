## Performance (milliseconds; idle_cpu_pct is a percentage of one core, idle_wakeups a count)

| Metric | Result | Baseline | Budget | Verdict | Notes |
|---|---|---|---|---|---|
| launch_overhead_ms | 289.54 | - | 150 | WARN | no baseline; over budget |
| keystroke_ms | 5.22 | 6.3 | 8 | OK |  |
| scroll_frame_ms | 6.79 | 5.8 | 8 | OK |  |
| switch_small_ms | 14.35 | 17.6 | 12 | WARN | over budget |
| switch_huge_ms | 33.27 | 65.9 | 50 | OK |  |
| paste_code_ms | 62.75 | 85.3 | 50 | WARN | over budget |
| idle_cpu_pct | 0.07 | - | 1 | WARN | no baseline |
| launch_ms | 838.99 | 776.1 | - | INFO | reported, not checked |
| launch_reference_ms | 342.76 | - | - | INFO | reported, not checked |
| launch_difference_ms | 496.23 | - | - | INFO | reported, not checked |
| scroll_frame_wall_ms | 12.47 | - | - | INFO | reported, not checked |
| scroll_frame_p95_ms | 16.83 | - | - | INFO | reported, not checked |
| scroll_frame_max_ms | 19.92 | - | - | INFO | reported, not checked |
| idle_wakeups | 3 | - | - | INFO | reported, not checked |
| launch_phase_main_ms | 111.35 | - | - | INFO | reported, not checked |
| launch_phase_storage_ms | 189.25 | - | - | INFO | reported, not checked |
| launch_phase_restore_ms | 509.25 | - | - | INFO | reported, not checked |
| launch_phase_window_ms | 605.95 | - | - | INFO | reported, not checked |
| launch_phase_firstFrame_ms | 844.8 | - | - | INFO | reported, not checked |

Result: PASS
