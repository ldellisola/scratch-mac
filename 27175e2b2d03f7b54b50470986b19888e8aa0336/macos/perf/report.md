## Performance (milliseconds; idle_cpu_pct is a percentage of one core, idle_wakeups a count)

| Metric | Result | Baseline | Budget | Verdict | Notes |
|---|---|---|---|---|---|
| launch_overhead_ms | 223.59 | - | 150 | WARN | no baseline; over budget |
| keystroke_ms | 5.12 | 6.3 | 8 | OK |  |
| scroll_frame_ms | 6.4 | 5.8 | 8 | OK |  |
| switch_small_ms | 15 | 17.6 | 12 | WARN | over budget |
| switch_huge_ms | 37.56 | 65.9 | 50 | OK |  |
| paste_code_ms | 93.08 | 85.3 | 50 | WARN | over budget |
| idle_cpu_pct | 0.34 | - | 1 | WARN | no baseline |
| launch_ms | 779.52 | 776.1 | - | INFO | reported, not checked |
| launch_reference_ms | 368.06 | - | - | INFO | reported, not checked |
| launch_difference_ms | 411.46 | - | - | INFO | reported, not checked |
| scroll_frame_wall_ms | 12.92 | - | - | INFO | reported, not checked |
| scroll_frame_p95_ms | 16.66 | - | - | INFO | reported, not checked |
| scroll_frame_max_ms | 27.08 | - | - | INFO | reported, not checked |
| idle_wakeups | 3 | - | - | INFO | reported, not checked |
| launch_phase_main_ms | 99.9 | - | - | INFO | reported, not checked |
| launch_phase_storage_ms | 179.15 | - | - | INFO | reported, not checked |
| launch_phase_restore_ms | 418.75 | - | - | INFO | reported, not checked |
| launch_phase_window_ms | 485.4 | - | - | INFO | reported, not checked |
| launch_phase_firstFrame_ms | 704.45 | - | - | INFO | reported, not checked |

Result: PASS
