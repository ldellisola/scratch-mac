## Performance (milliseconds; idle_cpu_pct is a percentage of one core, idle_wakeups a count)

| Metric | Result | Baseline | Budget | Verdict | Notes |
|---|---|---|---|---|---|
| launch_overhead_ms | 153.66 | - | 150 | WARN | no baseline; over budget |
| keystroke_ms | 4.87 | 6.3 | 8 | OK |  |
| scroll_frame_ms | 6 | 5.8 | 8 | OK |  |
| switch_small_ms | 9.3 | 17.6 | 12 | OK |  |
| switch_huge_ms | 29.16 | 65.9 | 50 | OK |  |
| paste_code_ms | 88.66 | 85.3 | 50 | WARN | over budget |
| idle_cpu_pct | 0.07 | - | 1 | WARN | no baseline |
| launch_ms | 409.36 | 776.1 | - | INFO | reported, not checked |
| launch_reference_ms | 231.5 | - | - | INFO | reported, not checked |
| launch_difference_ms | 177.86 | - | - | INFO | reported, not checked |
| scroll_frame_wall_ms | 11.72 | - | - | INFO | reported, not checked |
| scroll_frame_p95_ms | 17.13 | - | - | INFO | reported, not checked |
| scroll_frame_max_ms | 28.11 | - | - | INFO | reported, not checked |
| idle_wakeups | 3 | - | - | INFO | reported, not checked |
| launch_phase_main_ms | 58.85 | - | - | INFO | reported, not checked |
| launch_phase_storage_ms | 98.55 | - | - | INFO | reported, not checked |
| launch_phase_restore_ms | 252.55 | - | - | INFO | reported, not checked |
| launch_phase_window_ms | 295.4 | - | - | INFO | reported, not checked |
| launch_phase_firstFrame_ms | 420.85 | - | - | INFO | reported, not checked |

Result: PASS
