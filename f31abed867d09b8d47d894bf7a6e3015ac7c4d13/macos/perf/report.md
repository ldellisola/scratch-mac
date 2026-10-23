## Performance (milliseconds; idle_cpu_pct is a percentage of one core, idle_wakeups a count)

| Metric | Result | Baseline | Budget | Verdict | Notes |
|---|---|---|---|---|---|
| launch_overhead_ms | 99.21 | - | 150 | WARN | no baseline |
| keystroke_ms | 4.79 | 6.3 | 8 | OK |  |
| scroll_frame_ms | 5.43 | 5.8 | 8 | OK |  |
| switch_small_ms | 15.55 | 17.6 | 12 | WARN | over budget |
| switch_huge_ms | 40.94 | 65.9 | 50 | OK |  |
| paste_code_ms | 112.91 | 85.3 | 50 | FAIL | over 2x the budget; 32% slower than the baseline; over budget |
| idle_cpu_pct | 0.12 | - | 1 | WARN | no baseline |
| launch_ms | 835.04 | 776.1 | - | INFO | reported, not checked |
| launch_reference_ms | 558.17 | - | - | INFO | reported, not checked |
| launch_difference_ms | 276.87 | - | - | INFO | reported, not checked |
| scroll_frame_wall_ms | 9.98 | - | - | INFO | reported, not checked |
| scroll_frame_p95_ms | 14 | - | - | INFO | reported, not checked |
| scroll_frame_max_ms | 25.17 | - | - | INFO | reported, not checked |
| idle_wakeups | 4 | - | - | INFO | reported, not checked |
| launch_phase_main_ms | 110.5 | - | - | INFO | reported, not checked |
| launch_phase_storage_ms | 195.8 | - | - | INFO | reported, not checked |
| launch_phase_restore_ms | 490.9 | - | - | INFO | reported, not checked |
| launch_phase_window_ms | 589.9 | - | - | INFO | reported, not checked |
| launch_phase_firstFrame_ms | 890.45 | - | - | INFO | reported, not checked |

Result: FAIL
