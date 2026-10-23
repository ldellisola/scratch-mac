## Performance (milliseconds; idle_cpu_pct is a percentage of one core, idle_wakeups a count)

| Metric | Result | Baseline | Budget | Verdict | Notes |
|---|---|---|---|---|---|
| launch_overhead_ms | 145.63 | - | 150 | WARN | no baseline |
| keystroke_ms | 5.23 | 6.3 | 8 | OK |  |
| scroll_frame_ms | 0.76 | 5.8 | 8 | OK |  |
| switch_small_ms | 16.05 | 17.6 | 12 | WARN | over budget |
| switch_huge_ms | 30.99 | 65.9 | 50 | OK |  |
| paste_code_ms | 98.39 | 85.3 | 50 | WARN | over budget |
| idle_cpu_pct | 0.08 | - | 1 | WARN | no baseline |
| launch_ms | 535.19 | 776.1 | - | INFO | reported, not checked |
| launch_reference_ms | 309.69 | - | - | INFO | reported, not checked |
| launch_difference_ms | 225.5 | - | - | INFO | reported, not checked |
| scroll_frame_wall_ms | 0.77 | - | - | INFO | reported, not checked |
| scroll_frame_p95_ms | 12.84 | - | - | INFO | reported, not checked |
| scroll_frame_max_ms | 24.5 | - | - | INFO | reported, not checked |
| idle_wakeups | 3 | - | - | INFO | reported, not checked |
| launch_phase_main_ms | 76.05 | - | - | INFO | reported, not checked |
| launch_phase_storage_ms | 123.1 | - | - | INFO | reported, not checked |
| launch_phase_restore_ms | 329.65 | - | - | INFO | reported, not checked |
| launch_phase_window_ms | 399.5 | - | - | INFO | reported, not checked |
| launch_phase_firstFrame_ms | 554.75 | - | - | INFO | reported, not checked |

Result: PASS
