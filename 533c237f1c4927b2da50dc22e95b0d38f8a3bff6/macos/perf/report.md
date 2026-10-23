## Performance (milliseconds; idle_cpu_pct is a percentage of one core, idle_wakeups a count)

| Metric | Result | Baseline | Budget | Verdict | Notes |
|---|---|---|---|---|---|
| launch_overhead_ms | 176.4 | - | 150 | WARN | no baseline; over budget |
| keystroke_ms | 5.03 | 6.3 | 8 | OK |  |
| scroll_frame_ms | 0.72 | 5.8 | 8 | OK |  |
| switch_small_ms | 13.03 | 17.6 | 12 | WARN | over budget |
| switch_huge_ms | 27.19 | 65.9 | 50 | OK |  |
| paste_code_ms | 90.22 | 85.3 | 50 | WARN | over budget |
| idle_cpu_pct | 0.08 | - | 1 | WARN | no baseline |
| launch_ms | 555.2 | 776.1 | - | INFO | reported, not checked |
| launch_reference_ms | 295.01 | - | - | INFO | reported, not checked |
| launch_difference_ms | 260.19 | - | - | INFO | reported, not checked |
| scroll_frame_wall_ms | 0.74 | - | - | INFO | reported, not checked |
| scroll_frame_p95_ms | 16.55 | - | - | INFO | reported, not checked |
| scroll_frame_max_ms | 26.61 | - | - | INFO | reported, not checked |
| idle_wakeups | 3 | - | - | INFO | reported, not checked |
| launch_phase_main_ms | 75.7 | - | - | INFO | reported, not checked |
| launch_phase_storage_ms | 130.25 | - | - | INFO | reported, not checked |
| launch_phase_restore_ms | 358.35 | - | - | INFO | reported, not checked |
| launch_phase_window_ms | 424.75 | - | - | INFO | reported, not checked |
| launch_phase_firstFrame_ms | 563 | - | - | INFO | reported, not checked |

Result: PASS
