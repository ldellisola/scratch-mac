## Performance (milliseconds; idle_cpu_pct is a percentage of one core, idle_wakeups a count)

| Metric | Result | Baseline | Budget | Verdict | Notes |
|---|---|---|---|---|---|
| launch_overhead_ms | 163.22 | - | 150 | WARN | no baseline; over budget |
| keystroke_ms | 6.36 | 6.3 | 8 | OK |  |
| scroll_frame_ms | 6.68 | 5.8 | 8 | OK |  |
| switch_small_ms | 15.48 | 17.6 | 12 | WARN | over budget |
| switch_huge_ms | 36.91 | 65.9 | 50 | OK |  |
| paste_code_ms | 93.47 | 85.3 | 50 | WARN | over budget |
| idle_cpu_pct | 0.12 | - | 1 | WARN | no baseline |
| launch_ms | 629.75 | 776.1 | - | INFO | reported, not checked |
| launch_reference_ms | 346.76 | - | - | INFO | reported, not checked |
| launch_difference_ms | 282.99 | - | - | INFO | reported, not checked |
| scroll_frame_wall_ms | 13 | - | - | INFO | reported, not checked |
| scroll_frame_p95_ms | 16.27 | - | - | INFO | reported, not checked |
| scroll_frame_max_ms | 21.86 | - | - | INFO | reported, not checked |
| idle_wakeups | 3 | - | - | INFO | reported, not checked |
| launch_phase_main_ms | 76.4 | - | - | INFO | reported, not checked |
| launch_phase_storage_ms | 133.75 | - | - | INFO | reported, not checked |
| launch_phase_restore_ms | 377.7 | - | - | INFO | reported, not checked |
| launch_phase_window_ms | 431.55 | - | - | INFO | reported, not checked |
| launch_phase_firstFrame_ms | 611.15 | - | - | INFO | reported, not checked |

Result: PASS
