## Performance (milliseconds; idle_cpu_pct is a percentage of one core, idle_wakeups a count)

| Metric | Result | Baseline | Budget | Verdict | Notes |
|---|---|---|---|---|---|
| launch_overhead_ms | 165.65 | 287.26 | 150 | WARN | over budget |
| keystroke_ms | 4.74 | 6.31 | 8 | OK |  |
| scroll_frame_ms | 0.42 | 6.54 | 8 | OK |  |
| switch_small_ms | 10.13 | 16.64 | 12 | OK |  |
| switch_huge_ms | 26.85 | 34.39 | 50 | OK |  |
| paste_code_ms | 70.45 | 94.82 | 50 | WARN | over budget |
| idle_cpu_pct | 0.06 | 0.14 | 1 | OK |  |
| launch_ms | 514.09 | 816.7 | - | INFO | reported, not checked |
| launch_reference_ms | 281.19 | 335.22 | - | INFO | reported, not checked |
| launch_difference_ms | 232.9 | 481.48 | - | INFO | reported, not checked |
| scroll_frame_wall_ms | 0.42 | 12.37 | - | INFO | reported, not checked |
| scroll_frame_p95_ms | 9.24 | 16.55 | - | INFO | reported, not checked |
| scroll_frame_max_ms | 17.16 | 52.27 | - | INFO | reported, not checked |
| idle_wakeups | 4 | 3 | - | INFO | reported, not checked |
| launch_phase_main_ms | 74.05 | 122.45 | - | INFO | reported, not checked |
| launch_phase_storage_ms | 124.65 | 221.1 | - | INFO | reported, not checked |
| launch_phase_restore_ms | 317.75 | 562.25 | - | INFO | reported, not checked |
| launch_phase_window_ms | 375.4 | 674.55 | - | INFO | reported, not checked |
| launch_phase_firstFrame_ms | 534 | 1002.25 | - | INFO | reported, not checked |

Result: PASS
