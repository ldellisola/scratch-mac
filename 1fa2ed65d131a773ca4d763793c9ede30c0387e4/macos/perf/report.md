## Performance (milliseconds; idle_cpu_pct is a percentage of one core, idle_wakeups a count)

| Metric | Result | Baseline | Budget | Verdict | Notes |
|---|---|---|---|---|---|
| launch_overhead_ms | 174.53 | - | 150 | WARN | no baseline; over budget |
| keystroke_ms | 5.28 | 6.3 | 8 | OK |  |
| scroll_frame_ms | 0.53 | 5.8 | 8 | OK |  |
| switch_small_ms | 16.12 | 17.6 | 12 | WARN | over budget |
| switch_huge_ms | 33.99 | 65.9 | 50 | OK |  |
| paste_code_ms | 81.21 | 85.3 | 50 | WARN | over budget |
| idle_cpu_pct | 0.07 | - | 1 | WARN | no baseline |
| launch_ms | 590.31 | 776.1 | - | INFO | reported, not checked |
| launch_reference_ms | 315.23 | - | - | INFO | reported, not checked |
| launch_difference_ms | 275.09 | - | - | INFO | reported, not checked |
| scroll_frame_wall_ms | 0.54 | - | - | INFO | reported, not checked |
| scroll_frame_p95_ms | 10.12 | - | - | INFO | reported, not checked |
| scroll_frame_max_ms | 18.74 | - | - | INFO | reported, not checked |
| idle_wakeups | 3 | - | - | INFO | reported, not checked |
| launch_phase_main_ms | 75.6 | - | - | INFO | reported, not checked |
| launch_phase_storage_ms | 135.4 | - | - | INFO | reported, not checked |
| launch_phase_restore_ms | 362.7 | - | - | INFO | reported, not checked |
| launch_phase_window_ms | 430.6 | - | - | INFO | reported, not checked |
| launch_phase_firstFrame_ms | 612.25 | - | - | INFO | reported, not checked |

Result: PASS
