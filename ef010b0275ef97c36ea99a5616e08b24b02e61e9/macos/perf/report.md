## Performance (milliseconds; idle_cpu_pct is a percentage of one core, idle_wakeups a count)

| Metric | Result | Baseline | Budget | Verdict | Notes |
|---|---|---|---|---|---|
| launch_overhead_ms | 153.66 | - | 150 | WARN | no baseline; over budget |
| keystroke_ms | 3.74 | 6.3 | 8 | OK |  |
| scroll_frame_ms | 0.34 | 5.8 | 8 | OK |  |
| switch_small_ms | 8.77 | 17.6 | 12 | OK |  |
| switch_huge_ms | 22.89 | 65.9 | 50 | OK |  |
| paste_code_ms | 63.91 | 85.3 | 50 | WARN | over budget |
| idle_cpu_pct | 0.05 | - | 1 | WARN | no baseline |
| launch_ms | 454.13 | 776.1 | - | INFO | reported, not checked |
| launch_reference_ms | 256.82 | - | - | INFO | reported, not checked |
| launch_difference_ms | 197.32 | - | - | INFO | reported, not checked |
| scroll_frame_wall_ms | 0.34 | - | - | INFO | reported, not checked |
| scroll_frame_p95_ms | 5.16 | - | - | INFO | reported, not checked |
| scroll_frame_max_ms | 13.09 | - | - | INFO | reported, not checked |
| idle_wakeups | 3 | - | - | INFO | reported, not checked |
| launch_phase_main_ms | 64.6 | - | - | INFO | reported, not checked |
| launch_phase_storage_ms | 110.5 | - | - | INFO | reported, not checked |
| launch_phase_restore_ms | 283.45 | - | - | INFO | reported, not checked |
| launch_phase_window_ms | 338.45 | - | - | INFO | reported, not checked |
| launch_phase_firstFrame_ms | 492.05 | - | - | INFO | reported, not checked |

Result: PASS
