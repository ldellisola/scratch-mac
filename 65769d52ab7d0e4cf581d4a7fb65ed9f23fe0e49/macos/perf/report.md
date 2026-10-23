## Performance (milliseconds; idle_cpu_pct is a percentage of one core, idle_wakeups a count)

| Metric | Result | Baseline | Budget | Verdict | Notes |
|---|---|---|---|---|---|
| launch_overhead_ms | 176.09 | - | 150 | WARN | no baseline; over budget |
| keystroke_ms | 4.62 | 6.3 | 8 | OK |  |
| scroll_frame_ms | 0.63 | 5.8 | 8 | OK |  |
| switch_small_ms | 9.56 | 17.6 | 12 | OK |  |
| switch_huge_ms | 28.76 | 65.9 | 50 | OK |  |
| paste_code_ms | 73.9 | 85.3 | 50 | WARN | over budget |
| idle_cpu_pct | 0.08 | - | 1 | WARN | no baseline |
| launch_ms | 596.07 | 776.1 | - | INFO | reported, not checked |
| launch_reference_ms | 316.98 | - | - | INFO | reported, not checked |
| launch_difference_ms | 279.09 | - | - | INFO | reported, not checked |
| scroll_frame_wall_ms | 0.63 | - | - | INFO | reported, not checked |
| scroll_frame_p95_ms | 17.11 | - | - | INFO | reported, not checked |
| scroll_frame_max_ms | 40.03 | - | - | INFO | reported, not checked |
| idle_wakeups | 3 | - | - | INFO | reported, not checked |
| launch_phase_main_ms | 78 | - | - | INFO | reported, not checked |
| launch_phase_storage_ms | 137.4 | - | - | INFO | reported, not checked |
| launch_phase_restore_ms | 366.5 | - | - | INFO | reported, not checked |
| launch_phase_window_ms | 426.5 | - | - | INFO | reported, not checked |
| launch_phase_firstFrame_ms | 621.25 | - | - | INFO | reported, not checked |

Result: PASS
