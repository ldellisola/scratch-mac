## Performance (milliseconds; idle_cpu_pct is a percentage of one core, idle_wakeups a count)

| Metric | Result | Baseline | Budget | Verdict | Notes |
|---|---|---|---|---|---|
| launch_overhead_ms | 102.12 | - | 150 | WARN | no baseline |
| keystroke_ms | 3.7 | 6.3 | 8 | OK |  |
| scroll_frame_ms | 0.27 | 5.8 | 8 | OK |  |
| switch_small_ms | 8.13 | 17.6 | 12 | OK |  |
| switch_huge_ms | 24.73 | 65.9 | 50 | OK |  |
| paste_code_ms | 53.88 | 85.3 | 50 | WARN | over budget |
| idle_cpu_pct | 0.06 | - | 1 | WARN | no baseline |
| launch_ms | 425.14 | 776.1 | - | INFO | reported, not checked |
| launch_reference_ms | 281.44 | - | - | INFO | reported, not checked |
| launch_difference_ms | 143.7 | - | - | INFO | reported, not checked |
| scroll_frame_wall_ms | 0.27 | - | - | INFO | reported, not checked |
| scroll_frame_p95_ms | 2.63 | - | - | INFO | reported, not checked |
| scroll_frame_max_ms | 8.69 | - | - | INFO | reported, not checked |
| idle_wakeups | 3 | - | - | INFO | reported, not checked |
| launch_phase_main_ms | 59.25 | - | - | INFO | reported, not checked |
| launch_phase_storage_ms | 98.5 | - | - | INFO | reported, not checked |
| launch_phase_restore_ms | 257.9 | - | - | INFO | reported, not checked |
| launch_phase_window_ms | 304.4 | - | - | INFO | reported, not checked |
| launch_phase_firstFrame_ms | 447.25 | - | - | INFO | reported, not checked |

Result: PASS
