## Performance (milliseconds; idle_cpu_pct is a percentage of one core, idle_wakeups a count)

| Metric | Result | Baseline | Budget | Verdict | Notes |
|---|---|---|---|---|---|
| launch_overhead_ms | 115.46 | - | 150 | WARN | no baseline |
| keystroke_ms | 3.65 | 6.3 | 8 | OK |  |
| scroll_frame_ms | 0.38 | 5.8 | 8 | OK |  |
| switch_small_ms | 9.06 | 17.6 | 12 | OK |  |
| switch_huge_ms | 25.23 | 65.9 | 50 | OK |  |
| paste_code_ms | 52.94 | 85.3 | 50 | WARN | over budget |
| idle_cpu_pct | 0.07 | - | 1 | WARN | no baseline |
| launch_ms | 399.21 | 776.1 | - | INFO | reported, not checked |
| launch_reference_ms | 253.09 | - | - | INFO | reported, not checked |
| launch_difference_ms | 146.12 | - | - | INFO | reported, not checked |
| scroll_frame_wall_ms | 0.4 | - | - | INFO | reported, not checked |
| scroll_frame_p95_ms | 5.49 | - | - | INFO | reported, not checked |
| scroll_frame_max_ms | 13.77 | - | - | INFO | reported, not checked |
| idle_wakeups | 3 | - | - | INFO | reported, not checked |
| launch_phase_main_ms | 60.45 | - | - | INFO | reported, not checked |
| launch_phase_storage_ms | 99 | - | - | INFO | reported, not checked |
| launch_phase_restore_ms | 243.95 | - | - | INFO | reported, not checked |
| launch_phase_window_ms | 285.2 | - | - | INFO | reported, not checked |
| launch_phase_firstFrame_ms | 417.05 | - | - | INFO | reported, not checked |

Result: PASS
