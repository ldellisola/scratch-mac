## Performance (milliseconds; idle_cpu_pct is a percentage of one core, idle_wakeups a count)

| Metric | Result | Baseline | Budget | Verdict | Notes |
|---|---|---|---|---|---|
| launch_overhead_ms | 166.07 | - | 150 | WARN | no baseline; over budget |
| keystroke_ms | 3.87 | 6.3 | 8 | OK |  |
| scroll_frame_ms | 5.09 | 5.8 | 8 | OK |  |
| switch_small_ms | 8.19 | 17.6 | 12 | OK |  |
| switch_huge_ms | 25.42 | 65.9 | 50 | OK |  |
| paste_code_ms | 54.52 | 85.3 | 50 | WARN | over budget |
| idle_cpu_pct | 0.04 | - | 1 | WARN | no baseline |
| launch_ms | 453.16 | 776.1 | - | INFO | reported, not checked |
| launch_reference_ms | 247.58 | - | - | INFO | reported, not checked |
| launch_difference_ms | 205.58 | - | - | INFO | reported, not checked |
| scroll_frame_wall_ms | 9.85 | - | - | INFO | reported, not checked |
| scroll_frame_p95_ms | 8.41 | - | - | INFO | reported, not checked |
| scroll_frame_max_ms | 11.38 | - | - | INFO | reported, not checked |
| idle_wakeups | 3 | - | - | INFO | reported, not checked |
| launch_phase_main_ms | 61.85 | - | - | INFO | reported, not checked |
| launch_phase_storage_ms | 103.65 | - | - | INFO | reported, not checked |
| launch_phase_restore_ms | 274.3 | - | - | INFO | reported, not checked |
| launch_phase_window_ms | 319.3 | - | - | INFO | reported, not checked |
| launch_phase_firstFrame_ms | 473.6 | - | - | INFO | reported, not checked |

Result: PASS
