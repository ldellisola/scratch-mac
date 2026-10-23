## Performance (milliseconds; idle_cpu_pct is a percentage of one core, idle_wakeups a count)

| Metric | Result | Baseline | Budget | Verdict | Notes |
|---|---|---|---|---|---|
| launch_overhead_ms | 103.28 | - | 150 | WARN | no baseline |
| keystroke_ms | 4.83 | 6.3 | 8 | OK |  |
| scroll_frame_ms | 3.39 | 5.8 | 8 | OK |  |
| switch_small_ms | 12.88 | 17.6 | 12 | WARN | over budget |
| switch_huge_ms | 42.93 | 65.9 | 50 | OK |  |
| paste_code_ms | 82.76 | 85.3 | 50 | WARN | over budget |
| idle_cpu_pct | 0.17 | - | 1 | WARN | no baseline |
| launch_ms | 779.34 | 776.1 | - | INFO | reported, not checked |
| launch_reference_ms | 513.95 | - | - | INFO | reported, not checked |
| launch_difference_ms | 265.39 | - | - | INFO | reported, not checked |
| scroll_frame_wall_ms | 7.25 | - | - | INFO | reported, not checked |
| scroll_frame_p95_ms | 12.7 | - | - | INFO | reported, not checked |
| scroll_frame_max_ms | 19.87 | - | - | INFO | reported, not checked |
| idle_wakeups | 3 | - | - | INFO | reported, not checked |
| launch_phase_main_ms | 91.45 | - | - | INFO | reported, not checked |
| launch_phase_storage_ms | 159.05 | - | - | INFO | reported, not checked |
| launch_phase_restore_ms | 432.15 | - | - | INFO | reported, not checked |
| launch_phase_window_ms | 499.35 | - | - | INFO | reported, not checked |
| launch_phase_firstFrame_ms | 768.45 | - | - | INFO | reported, not checked |

Result: PASS
