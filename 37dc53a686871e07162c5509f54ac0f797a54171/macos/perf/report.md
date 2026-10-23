## Performance (milliseconds; idle_cpu_pct is a percentage of one core, idle_wakeups a count)

| Metric | Result | Baseline | Budget | Verdict | Notes |
|---|---|---|---|---|---|
| launch_overhead_ms | 172.16 | 287.26 | 150 | WARN | over budget |
| keystroke_ms | 4.96 | 6.31 | 8 | OK |  |
| scroll_frame_ms | 6.25 | 6.54 | 8 | OK |  |
| switch_small_ms | 9.2 | 16.64 | 12 | OK |  |
| switch_huge_ms | 27.3 | 34.39 | 50 | OK |  |
| paste_code_ms | 86.67 | 94.82 | 50 | WARN | over budget |
| idle_cpu_pct | 0.05 | 0.14 | 1 | OK |  |
| launch_ms | 459.74 | 816.7 | - | INFO | reported, not checked |
| launch_reference_ms | 247.06 | 335.22 | - | INFO | reported, not checked |
| launch_difference_ms | 212.68 | 481.48 | - | INFO | reported, not checked |
| scroll_frame_wall_ms | 11.68 | 12.37 | - | INFO | reported, not checked |
| scroll_frame_p95_ms | 8.15 | 16.55 | - | INFO | reported, not checked |
| scroll_frame_max_ms | 14.59 | 52.27 | - | INFO | reported, not checked |
| idle_wakeups | 3 | 3 | - | INFO | reported, not checked |
| launch_phase_main_ms | 64.15 | 122.45 | - | INFO | reported, not checked |
| launch_phase_storage_ms | 108.9 | 221.1 | - | INFO | reported, not checked |
| launch_phase_restore_ms | 281.2 | 562.25 | - | INFO | reported, not checked |
| launch_phase_window_ms | 336.95 | 674.55 | - | INFO | reported, not checked |
| launch_phase_firstFrame_ms | 491 | 1002.25 | - | INFO | reported, not checked |

Result: PASS
