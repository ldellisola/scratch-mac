## Performance (milliseconds; idle_cpu_pct is a percentage of one core, idle_wakeups a count)

| Metric | Result | Baseline | Budget | Verdict | Notes |
|---|---|---|---|---|---|
| launch_overhead_ms | 161.71 | - | 150 | WARN | no baseline; over budget |
| keystroke_ms | 22.61 | 6.3 | 8 | FAIL | over 2x the budget; 259% slower than the baseline; over budget |
| scroll_frame_ms | 5.04 | 5.8 | 8 | OK |  |
| switch_small_ms | 9.1 | 17.6 | 12 | OK |  |
| switch_huge_ms | 26.33 | 65.9 | 50 | OK |  |
| paste_code_ms | 92.03 | 85.3 | 50 | WARN | over budget |
| idle_cpu_pct | 0.24 | - | 1 | WARN | no baseline |
| launch_ms | 500.2 | 776.1 | - | INFO | reported, not checked |
| launch_reference_ms | 276.58 | - | - | INFO | reported, not checked |
| launch_difference_ms | 223.62 | - | - | INFO | reported, not checked |
| scroll_frame_wall_ms | 8.67 | - | - | INFO | reported, not checked |
| scroll_frame_p95_ms | 8.7 | - | - | INFO | reported, not checked |
| scroll_frame_max_ms | 18.48 | - | - | INFO | reported, not checked |
| idle_wakeups | 3 | - | - | INFO | reported, not checked |
| launch_phase_main_ms | 67.15 | - | - | INFO | reported, not checked |
| launch_phase_storage_ms | 117.25 | - | - | INFO | reported, not checked |
| launch_phase_restore_ms | 299.45 | - | - | INFO | reported, not checked |
| launch_phase_window_ms | 357.25 | - | - | INFO | reported, not checked |
| launch_phase_firstFrame_ms | 523.15 | - | - | INFO | reported, not checked |

Result: FAIL
