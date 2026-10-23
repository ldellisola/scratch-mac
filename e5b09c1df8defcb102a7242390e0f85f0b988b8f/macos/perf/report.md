## Performance (milliseconds; idle_cpu_pct is a percentage of one core, idle_wakeups a count)

| Metric | Result | Baseline | Budget | Verdict | Notes |
|---|---|---|---|---|---|
| launch_overhead_ms | 174.06 | - | 150 | WARN | no baseline; over budget |
| keystroke_ms | 4.6 | 6.3 | 8 | OK |  |
| scroll_frame_ms | 6.02 | 5.8 | 8 | OK |  |
| switch_small_ms | 11.36 | 17.6 | 12 | OK |  |
| switch_huge_ms | 27.8 | 65.9 | 50 | OK |  |
| paste_code_ms | 72.97 | 85.3 | 50 | WARN | over budget |
| idle_cpu_pct | 0.07 | - | 1 | WARN | no baseline |
| launch_ms | 564.7 | 776.1 | - | INFO | reported, not checked |
| launch_reference_ms | 301.94 | - | - | INFO | reported, not checked |
| launch_difference_ms | 262.77 | - | - | INFO | reported, not checked |
| scroll_frame_wall_ms | 11.3 | - | - | INFO | reported, not checked |
| scroll_frame_p95_ms | 14.97 | - | - | INFO | reported, not checked |
| scroll_frame_max_ms | 28.65 | - | - | INFO | reported, not checked |
| idle_wakeups | 3 | - | - | INFO | reported, not checked |
| launch_phase_main_ms | 76.8 | - | - | INFO | reported, not checked |
| launch_phase_storage_ms | 133.5 | - | - | INFO | reported, not checked |
| launch_phase_restore_ms | 347.5 | - | - | INFO | reported, not checked |
| launch_phase_window_ms | 402.1 | - | - | INFO | reported, not checked |
| launch_phase_firstFrame_ms | 600.65 | - | - | INFO | reported, not checked |

Result: PASS
