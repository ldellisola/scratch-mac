## Performance (milliseconds; idle_cpu_pct is a percentage of one core, idle_wakeups a count)

| Metric | Result | Baseline | Budget | Verdict | Notes |
|---|---|---|---|---|---|
| launch_overhead_ms | 111.93 | - | 150 | WARN | no baseline |
| keystroke_ms | 5.12 | 6.3 | 8 | OK |  |
| scroll_frame_ms | 0.76 | 5.8 | 8 | OK |  |
| switch_small_ms | 12.11 | 17.6 | 12 | WARN | over budget |
| switch_huge_ms | 27.64 | 65.9 | 50 | OK |  |
| paste_code_ms | 79.48 | 85.3 | 50 | WARN | over budget |
| idle_cpu_pct | 0.18 | - | 1 | WARN | no baseline |
| launch_ms | 700.67 | 776.1 | - | INFO | reported, not checked |
| launch_reference_ms | 449.25 | - | - | INFO | reported, not checked |
| launch_difference_ms | 251.42 | - | - | INFO | reported, not checked |
| scroll_frame_wall_ms | 0.78 | - | - | INFO | reported, not checked |
| scroll_frame_p95_ms | 17.21 | - | - | INFO | reported, not checked |
| scroll_frame_max_ms | 37.33 | - | - | INFO | reported, not checked |
| idle_wakeups | 3 | - | - | INFO | reported, not checked |
| launch_phase_main_ms | 88.45 | - | - | INFO | reported, not checked |
| launch_phase_storage_ms | 156.25 | - | - | INFO | reported, not checked |
| launch_phase_restore_ms | 420.35 | - | - | INFO | reported, not checked |
| launch_phase_window_ms | 487 | - | - | INFO | reported, not checked |
| launch_phase_firstFrame_ms | 707.4 | - | - | INFO | reported, not checked |

Result: PASS
