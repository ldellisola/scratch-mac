## Performance (milliseconds; idle_cpu_pct is a percentage of one core, idle_wakeups a count)

| Metric | Result | Baseline | Budget | Verdict | Notes |
|---|---|---|---|---|---|
| launch_overhead_ms | 111.43 | - | 150 | WARN | no baseline |
| keystroke_ms | 5.12 | 6.3 | 8 | OK |  |
| scroll_frame_ms | 0.76 | 5.8 | 8 | OK |  |
| switch_small_ms | 9.74 | 17.6 | 12 | OK |  |
| switch_huge_ms | 27.69 | 65.9 | 50 | OK |  |
| paste_code_ms | 50.2 | 85.3 | 50 | WARN | over budget |
| idle_cpu_pct | 0.04 | - | 1 | WARN | no baseline |
| launch_ms | 551.45 | 776.1 | - | INFO | reported, not checked |
| launch_reference_ms | 354.14 | - | - | INFO | reported, not checked |
| launch_difference_ms | 197.31 | - | - | INFO | reported, not checked |
| scroll_frame_wall_ms | 0.77 | - | - | INFO | reported, not checked |
| scroll_frame_p95_ms | 17.44 | - | - | INFO | reported, not checked |
| scroll_frame_max_ms | 31.03 | - | - | INFO | reported, not checked |
| idle_wakeups | 3 | - | - | INFO | reported, not checked |
| launch_phase_main_ms | 69.95 | - | - | INFO | reported, not checked |
| launch_phase_storage_ms | 119.9 | - | - | INFO | reported, not checked |
| launch_phase_restore_ms | 313.4 | - | - | INFO | reported, not checked |
| launch_phase_window_ms | 368.25 | - | - | INFO | reported, not checked |
| launch_phase_firstFrame_ms | 528.75 | - | - | INFO | reported, not checked |

Result: PASS
