## Performance (milliseconds; idle_cpu_pct is a percentage of one core, idle_wakeups a count)

| Metric | Result | Baseline | Budget | Verdict | Notes |
|---|---|---|---|---|---|
| launch_overhead_ms | 175.49 | - | 150 | WARN | no baseline; over budget |
| keystroke_ms | 4.5 | 6.3 | 8 | OK |  |
| scroll_frame_ms | 0.3 | 5.8 | 8 | OK |  |
| switch_small_ms | 9.73 | 17.6 | 12 | OK |  |
| switch_huge_ms | 25.78 | 65.9 | 50 | OK |  |
| paste_code_ms | 71.16 | 85.3 | 50 | WARN | over budget |
| idle_cpu_pct | 0.15 | - | 1 | WARN | no baseline |
| launch_ms | 504.41 | 776.1 | - | INFO | reported, not checked |
| launch_reference_ms | 268.67 | - | - | INFO | reported, not checked |
| launch_difference_ms | 235.74 | - | - | INFO | reported, not checked |
| scroll_frame_wall_ms | 0.3 | - | - | INFO | reported, not checked |
| scroll_frame_p95_ms | 4.94 | - | - | INFO | reported, not checked |
| scroll_frame_max_ms | 11.71 | - | - | INFO | reported, not checked |
| idle_wakeups | 3 | - | - | INFO | reported, not checked |
| launch_phase_main_ms | 72.75 | - | - | INFO | reported, not checked |
| launch_phase_storage_ms | 124.6 | - | - | INFO | reported, not checked |
| launch_phase_restore_ms | 327.7 | - | - | INFO | reported, not checked |
| launch_phase_window_ms | 392.15 | - | - | INFO | reported, not checked |
| launch_phase_firstFrame_ms | 531.3 | - | - | INFO | reported, not checked |

Result: PASS
